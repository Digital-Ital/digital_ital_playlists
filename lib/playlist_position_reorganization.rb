# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"
require "yaml"

# Plans a reversible, position-only update based on the curator's 110-title directory.
# No records are modified until apply! runs with the exact preview fingerprint.
class PlaylistPositionReorganization
  BRANCHES = %w[vocal dub soundsystem history lyrical political cannabis other].freeze
  PREFIXES = BRANCHES.to_h { |branch| [branch, (BRANCHES.index(branch) + 1) * 100] }.freeze
  BACKUP_PREFIX = "playlist-position-reorder:".freeze
  ROLLBACK_PREFIX = "playlist-position-rollback:".freeze

  def initialize
    manifest = YAML.safe_load_file(Rails.root.join("config/playlist_position_manifest.yml"))
    @branches = manifest.fetch("branches")
    raise "Unexpected branch configuration" unless @branches.keys == BRANCHES

    @reserved = {}
    @by_title = {}
    @categories = {}
    BRANCHES.each do |branch|
      config = @branches.fetch(branch)
      @categories[config.fetch("category")] = branch
      @reserved[branch] = {}
      config.fetch("slots").each do |slot|
        title = slot.fetch("title")
        position = Integer(slot.fetch("position"))
        raise "Invalid reserved position #{position} for #{branch}" unless (PREFIXES.fetch(branch)...PREFIXES.fetch(branch) + 100).cover?(position)
        raise "Duplicate reserved position #{position}" if @reserved[branch].key?(position)
        key = normalize(title)
        raise "Duplicate normalized title: #{title}" if @by_title.key?(key)

        @reserved[branch][position] = title
        @by_title[key] = { branch: branch, position: position }
      end
    end
  end

  # Returns the full catalog as a deterministic, reviewable proposal.
  # The fingerprint changes if a title, category, position, or playlist ID changes.
  def plan(playlists = Playlist.includes(:categories).order(:id).to_a)
    listings = playlists.map do |playlist|
      {
        id: playlist.id,
        title: playlist.title,
        old_position: playlist.position,
        categories: playlist.categories.map(&:name).sort
      }
    end
    fingerprint = Digest::SHA256.hexdigest(JSON.generate(listings))
    used = {}
    entries = listings.map do |item|
      known = @by_title[normalize(item.fetch(:title))]
      branch = known ? known.fetch(:branch) : infer_branch(item)
      new_position = known && known.fetch(:position)
      if new_position
        raise "Duplicate live playlist for reserved slot #{new_position}" if used.key?(new_position)

        used[new_position] = item.fetch(:id)
      end

      item.merge(branch: branch, new_position: new_position, match: known ? "manifest" : "inferred")
    end

    entries.select { |item| item[ :new_position ].nil? }
           .group_by { |item| item.fetch(:branch) }
           .each do |branch, items|
      block_start = PREFIXES.fetch(branch)
      reserved = @reserved.fetch(branch).keys
      # Keep every curator-reserved position free even if its playlist is not live.
      taken = (reserved + used.keys).to_h { |position| [position, true] }
      extra_start = [reserved.max || block_start, block_start].max + 4
      items.sort_by { |item| [item.fetch(:title).downcase, item.fetch(:id)] }.each do |item|
        volume = item[ :title ].match(/\bVol(?:ume)?\.?\s*0*(\d+)\b/i)
        candidate = volume && volume[1].to_i.between?(1, 22) ? block_start + 1 + 4 * (volume[1].to_i - 1) : nil
        candidate = nil if candidate && taken[candidate]
        candidate ||= ((extra_start...(block_start + 100)).find { |position| !taken[position] })
        raise "Branch #{branch} has no space for #{item[ :title ]}" unless candidate

        item[ :new_position ] = candidate
        used[candidate] = item[ :id ]
        taken[candidate] = true
        extra_start = [extra_start, candidate + 1].max
      end
    end

    positions = entries.map { |item| item.fetch(:new_position) }
    raise "Duplicate proposed positions" unless positions.uniq.size == positions.size

    { fingerprint: fingerprint, entries: entries.sort_by { |item| [item.fetch(:new_position), item.fetch(:id)] } }
  end

  def apply!(expected_fingerprint:)
    raise "PREVIEW_SHA is required" if expected_fingerprint.to_s.empty?

    batch_id = SecureRandom.hex(12)
    changed = nil
    Playlist.transaction do
      playlists = Playlist.order(:id).lock.includes(:categories).to_a
      proposal = plan(playlists)
      raise "Playlist data changed since preview; rerun preview" unless proposal.fetch(:fingerprint) == expected_fingerprint

      changed = proposal.fetch(:entries).select { |item| item[ :old_position ] != item[ :new_position ] }
      changed.each do |item|
        playlist = playlists.find { |candidate| candidate.id == item.fetch(:id) }
        UpdateLog.create!(
          playlist: playlist,
          log_type: "playlist_metadata",
          field_name: "position",
          old_value: item[ :old_position ]&.to_s,
          new_value: item.fetch(:new_position).to_s,
          change_summary: "#{BACKUP_PREFIX}#{batch_id}"
        )
        playlist.update_columns(position: item.fetch(:new_position))
      end
    end
    { batch_id: batch_id, changed: changed.length }
  end

  def rollback!(batch_id:)
    raise "BATCH is required" if batch_id.to_s.empty?
    raise "Invalid batch ID" unless batch_id.match?(/\A[0-9a-f]{24}\z/)

    count = nil
    Playlist.transaction do
      logs = UpdateLog.where(
        log_type: "playlist_metadata", field_name: "position",
        change_summary: "#{BACKUP_PREFIX}#{batch_id}"
      ).order(:id).to_a
      raise "No backup logs found for this batch" if logs.empty?
      raise "Batch has already been rolled back" if UpdateLog.exists?(change_summary: "#{ROLLBACK_PREFIX}#{batch_id}")
      raise "Duplicate playlist IDs in backup" unless logs.map(&:playlist_id).uniq.size == logs.size

      playlists = Playlist.where(id: logs.map(&:playlist_id)).order(:id).lock.index_by(&:id)
      raise "A playlist from the backup is missing" unless playlists.length == logs.length
      logs.each do |log|
        playlist = playlists.fetch(log.playlist_id)
        raise "Position has changed since apply: #{playlist.title}" unless playlist.position.to_s == log.new_value.to_s
      end

      logs.each do |log|
        playlist = playlists.fetch(log.playlist_id)
        old_position = log.old_value.nil? ? nil : Integer(log.old_value)
        playlist.update_columns(position: old_position)
        UpdateLog.create!(
          playlist: playlist,
          log_type: "playlist_metadata",
          field_name: "position",
          old_value: log.new_value,
          new_value: log.old_value,
          change_summary: "#{ROLLBACK_PREFIX}#{batch_id}"
        )
      end
      count = logs.length
    end
    count
  end

  private

  def normalize(title)
    I18n.transliterate(title.to_s).downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  def infer_branch(item)
    title = item.fetch(:title)
    return "political" if title.match?(/\A(?:Political Reggae|Revolutionary Hip-Hop)/i)
    return "cannabis" if title.match?(/\A(?:Cannabis Songs|Marijuana)/i)
    return "dub" if title.match?(/\A(?:Dub Instrumentals|Dub Vol)/i)
    return "soundsystem" if title.match?(/\A(?:Rub-a-Dub|Dubwise)/i)
    return "vocal" if title.match?(/\A(?:Reggae(?:\s|\s*&)|Rock-Reggae-Ska)/i)
    return "lyrical" if title.match?(/\A(?:Lyrical Hip-Hop|Hip-Hop\/Rap)/i)

    matches = item.fetch(:categories).filter_map { |name| @categories[name] }
    matches.first || "other"
  end
end
