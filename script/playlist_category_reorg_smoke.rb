# frozen_string_literal: true

require "tempfile"
require "yaml"

raise "Refusing to run on a non-test database" unless Rails.env.test?

# The production manifest must contain precisely the 66 curator-approved actions.
approved = PlaylistCategoryReorganization.new
raise "Approved action count mismatch" unless approved.instruction_count == 66

beats = Category.create!(name: "Hip-Hop Beats / Instrumentals")
sound = Category.create!(name: "Rub-a-Dub / Sound System Branch")
lyrical = Category.create!(name: "Lyrical Rap Branch")
Category.create!(name: "Cannabis Crates")

first = Playlist.create!(title: "Existing Instrumental Beat Crate", position: 801, track_count: 12)
second = Playlist.create!(title: "Mistagged Rap Crate", position: 701, track_count: 12)
third = Playlist.create!(title: "Lyrical Music", position: 501, track_count: 12)
first.categories << beats
second.categories << sound
third.categories << lyrical

manifest = {
  "expected_playlist_count" => 3,
  "expected_inventory_sha256" => "pending",
  "expected_additions" => 2,
  "expected_removals" => 1,
  "expected_actions" => 4,
  "rename" => {
    "from" => "Hip-Hop Beats / Instrumentals",
    "to" => "Cross-Genre & Instrumentals",
    "preserve_slug" => true
  },
  "add" => {
    "Cross-Genre & Instrumentals" => [ second.id ],
    "Cannabis Crates" => [ third.id ]
  },
  "remove" => { "Rub-a-Dub / Sound System Branch" => [ second.id ] }
}

Tempfile.create([ "category-reorg-test", ".yml" ]) do |temp|
  temp.write(YAML.dump(manifest))
  temp.flush
  scanner = PlaylistCategoryReorganization.new(manifest_path: temp.path)
  manifest["expected_inventory_sha256"] = scanner.inventory_digest(Playlist.includes(:categories).order(:id).to_a)
  temp.rewind
  temp.truncate(0)
  temp.write(YAML.dump(manifest))
  temp.flush

  reorganization = PlaylistCategoryReorganization.new(manifest_path: temp.path)
  proposed = reorganization.preview
  raise "Preview changed database" unless second.reload.category_ids == [ sound.id ]
  raise "Wrong expected proposal" unless proposed.fetch(:additions) == 2 && proposed.fetch(:removals) == 1
  raise "Wrong affected playlist count" unless proposed.fetch(:changes).length == 2

  batch = reorganization.apply!
  raise "Apply changed position" unless second.reload.position == 701
  raise "Wrong membership after apply" unless second.category_ids == [ beats.id ]
  raise "Cannabis category not linked" unless third.reload.categories.map(&:name).include?("Cannabis Crates")
  raise "Category rename missing" unless beats.reload.name == "Cross-Genre & Instrumentals"
  raise "Category URL changed" unless beats.slug == "hip-hop-beats-instrumentals"
  raise "Incorrect backup count" unless UpdateLog.where(change_summary: "playlist-category-reorg:#{batch.fetch(:batch_id)}").count == 3

  begin
    reorganization.apply!
    raise "Repeat apply should have been refused"
  rescue RuntimeError => e
    raise unless e.message.include?("differ from approved inventory")
  end

  # Rollback must reject intervening user edits rather than overwriting them.
  third.categories << sound
  begin
    reorganization.rollback!(batch_id: batch.fetch(:batch_id))
    raise "Conflicting rollback should have been refused"
  rescue RuntimeError => e
    raise unless e.message.include?("changed since apply")
  end
  raise "Rollback partly executed" unless beats.reload.name == "Cross-Genre & Instrumentals"

  third.categories.delete(sound)
  restored = reorganization.rollback!(batch_id: batch.fetch(:batch_id))
  raise "Wrong rollback count" unless restored == 2
  raise "Original category name not restored" unless beats.reload.name == "Hip-Hop Beats / Instrumentals"
  raise "Original Sound System membership not restored" unless second.reload.category_ids == [ sound.id ]
  raise "Original lyrical membership not restored" unless third.reload.category_ids == [ lyrical.id ]
  raise "Slug changed in rollback" unless beats.slug == "hip-hop-beats-instrumentals"

  begin
    reorganization.rollback!(batch_id: batch.fetch(:batch_id))
    raise "Second rollback should have been refused"
  rescue RuntimeError => e
    raise unless e.message.include?("already been rolled back")
  end
end

puts "Category audit smoke test passed: preview, apply, URL preservation, conflict protection and rollback"
