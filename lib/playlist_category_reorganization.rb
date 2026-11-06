# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"
require "yaml"

# An explicit, one-time reconciliation of the curator-approved November 2026
# category audit. No database writes are performed by loading this class.
class PlaylistCategoryReorganization
  APPLY_LOG_PREFIX = "playlist-category-reorg:"
  ROLLBACK_LOG_PREFIX = "playlist-category-reorg-rollback:"

  def initialize(manifest_path: Rails.root.join("config/approved_category_audit_2026_11_06.yml"))
    @manifest = YAML.safe_load_file(manifest_path)
    @rename = @manifest.fetch("rename")
    @add = @manifest.fetch("add")
    @remove = @manifest.fetch("remove")
  end

  def instruction_count
    @add.values.sum(&:length) + @remove.values.sum(&:length) + 1
  end

  def inventory_digest(playlists)
    data = playlists.sort_by(&:id).map do |playlist|
      "#{playlist.id}\t#{playlist.position}\t#{playlist.categories.map(&:name).sort.join('|')}\n"
    end.join
    Digest::SHA256.hexdigest(data)
  end

  def preview
    build_plan(Playlist.includes(:categories).order(:id).to_a)
  end

  def apply!
    batch_id = SecureRandom.hex(12)
    output = nil

    Playlist.transaction do
      playlists = Playlist.includes(:categories).order(:id).lock.to_a
      plan = build_plan(playlists)
      category_id = plan.fetch(:renamed_category_id)

      # Capture the existing join-table category IDs before making ANY change.
      plan.fetch(:changes).each do |item|
        playlist = playlists.find { |record| record.id == item.fetch(:id) }
        old_ids = item.fetch(:old_category_ids)
        new_ids = item.fetch(:new_category_ids)
        UpdateLog.create!(
          playlist: playlist,
          log_type: "playlist_metadata",
          field_name: "category_ids",
          old_value: JSON.generate(old_ids),
          new_value: JSON.generate(new_ids),
          change_summary: "#{APPLY_LOG_PREFIX}#{batch_id}"
        )
        playlist.category_ids = new_ids
      end

      # Keep the current slug and category ID: existing URLs and relationships
      # continue working after the visible name changes.
      Category.find(category_id).update_columns(
        name: @rename.fetch("to"), updated_at: Time.current
      )
      UpdateLog.create!(
        playlist: playlists.first,
        log_type: "playlist_metadata",
        field_name: "category_name",
        old_value: @rename.fetch("from"),
        new_value: @rename.fetch("to"),
        change_summary: "#{APPLY_LOG_PREFIX}#{batch_id}"
      )
      output = {
        batch_id: batch_id,
        playlists_changed: plan.fetch(:changes).length,
        additions: plan.fetch(:additions),
        removals: plan.fetch(:removals),
        category_renamed: true
      }
    end

    output
  end

  def rollback!(batch_id:)
    raise "Invalid BATCH (must be 24 hexadecimal characters)" unless batch_id.to_s.match?(/\A[0-9a-f]{24}\z/)

    summary = "#{APPLY_LOG_PREFIX}#{batch_id}"
    count = nil

    Playlist.transaction do
      logs = UpdateLog.where(change_summary: summary).order(:id).to_a
      memberships = logs.select { |log| log.field_name == "category_ids" }
      rename_log = logs.find { |log| log.field_name == "category_name" }
      raise "No complete category backup found for batch" if rename_log.nil? || memberships.empty?
      raise "Unexpected records in category backup" unless logs.length == memberships.length + 1
      raise "Duplicate playlist in backup" unless memberships.map(&:playlist_id).uniq.length == memberships.length
      if UpdateLog.exists?(change_summary: "#{ROLLBACK_LOG_PREFIX}#{batch_id}")
        raise "This category batch has already been rolled back"
      end

      category = Category.lock.find_by!(name: rename_log.new_value)
      if Category.exists?(name: rename_log.old_value)
        raise "Original category name is now in use; cannot safely roll back"
      end

      playlists = Playlist.where(id: memberships.map(&:playlist_id)).order(:id).lock.index_by(&:id)
      raise "A playlist from the backup is missing" unless playlists.length == memberships.length

      memberships.each do |log|
        current_ids = playlists.fetch(log.playlist_id).category_ids.sort
        expected_ids = JSON.parse(log.new_value).map(&:to_i).sort
        if current_ids != expected_ids
          raise "Categories changed since apply for playlist #{log.playlist_id}; rollback refused"
        end
      end

      memberships.each do |log|
        playlists.fetch(log.playlist_id).category_ids = JSON.parse(log.old_value).map(&:to_i)
      end
      category.update_columns(name: rename_log.old_value, updated_at: Time.current)
      UpdateLog.create!(
        playlist: playlists.values.first,
        log_type: "playlist_metadata",
        field_name: "category_reorg_rollback",
        old_value: rename_log.new_value,
        new_value: rename_log.old_value,
        change_summary: "#{ROLLBACK_LOG_PREFIX}#{batch_id}"
      )
      count = memberships.length
    end

    count
  end

  private

  def build_plan(playlists)
    expected_count = Integer(@manifest.fetch("expected_playlist_count"))
    raise "Inventory count changed (#{playlists.length} != #{expected_count})" unless playlists.length == expected_count

    digest = inventory_digest(playlists)
    expected_digest = @manifest.fetch("expected_inventory_sha256")
    raise "Live categories/positions differ from approved inventory; new audit needed" unless digest == expected_digest

    original_name = @rename.fetch("from")
    target_name = @rename.fetch("to")
    raise "Renamed category already exists" if Category.exists?(name: target_name)
    source_category = Category.find_by!(name: original_name)
    raise "Cannot change slug" unless @rename.fetch("preserve_slug") == true

    categories = Category.all.index_by(&:name)
    category_ids_by_name = categories.transform_values(&:id).merge(target_name => source_category.id)
    instructions = Hash.new { |hash, id| hash[id] = { add: [], remove: [] } }

    @add.each do |name, ids|
      raise "Unknown category: #{name}" unless category_ids_by_name.key?(name)

      ids.each { |id| instructions[Integer(id)][:add] << name }
    end
    @remove.each do |name, ids|
      raise "Unknown category: #{name}" unless category_ids_by_name.key?(name)

      ids.each { |id| instructions[Integer(id)][:remove] << name }
    end

    raise "No category actions found" if instructions.empty?
    raise "Duplicate category actions" unless @add.values.flatten.uniq.length <= @add.values.flatten.length
    indexed = playlists.index_by(&:id)
    changes = []
    additions = 0
    removals = 0

    instructions.sort.each do |playlist_id, instruction|
      playlist = indexed.fetch(playlist_id) { raise "Playlist #{playlist_id} no longer exists" }
      old_ids = playlist.categories.map(&:id).sort
      new_ids = old_ids.dup

      instruction.fetch(:add).each do |name|
        category_id = category_ids_by_name.fetch(name)
        raise "Already in category #{name}: playlist #{playlist_id}" if new_ids.include?(category_id)

        new_ids << category_id
        additions += 1
      end
      instruction.fetch(:remove).each do |name|
        category_id = category_ids_by_name.fetch(name)
        raise "Category absent #{name}: playlist #{playlist_id}" unless new_ids.include?(category_id)

        new_ids.delete(category_id)
        removals += 1
      end
      raise "No categories left for playlist #{playlist_id}" if new_ids.empty?
      changes << {
        id: playlist_id,
        title: playlist.title,
        position: playlist.position,
        old_category_ids: old_ids,
        new_category_ids: new_ids.sort,
        add: instruction.fetch(:add),
        remove: instruction.fetch(:remove)
      }
    end

    raise "Expected 62 additions, got #{additions}" unless additions == 62 && @manifest.fetch("expected_playlist_count") == 110
    raise "Expected 3 removals, got #{removals}" unless removals == 3 && instruction_count == 66

    {
      inventory_sha256: digest,
      changes: changes.sort_by { |row| [ row.fetch(:position), row.fetch(:id) ] },
      additions: additions,
      removals: removals,
      rename_from: original_name,
      rename_to: target_name,
      renamed_category_id: source_category.id,
      category_slug: source_category.slug
    }
  end
end
