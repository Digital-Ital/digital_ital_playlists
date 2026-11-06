# frozen_string_literal: true

# CI-only smoke test against disposable RAILS_ENV=test SQLite data.
raise "Do not run against production" unless Rails.env.test?

manifest = YAML.safe_load_file(Rails.root.join("config/playlist_position_manifest.yml")).fetch("branches")
dub_title = manifest.fetch("dub").fetch("slots").first.fetch("title")
political_title = manifest.fetch("political").fetch("slots").first.fetch("title")

dub = Playlist.create!(title: dub_title, track_count: 12, position: 8)
political = Playlist.create!(title: political_title, track_count: 12, position: nil)
missing_volume = Playlist.create!(title: "Dub Instrumentals Vol. 11: New Future Crate", track_count: 12, position: 99)
extra = Playlist.create!(title: "Additional Protest Archive", track_count: 12, position: 45)
category = Category.create!(name: "Political Crates")
extra.categories << category

planner = PlaylistPositionReorganization.new
proposal = planner.plan
by_id = proposal.fetch(:entries).index_by { |row| row.fetch(:id) }

raise "Curated Dub slot changed" unless by_id.fetch(dub.id).fetch(:new_position) == 201
raise "Curated political slot changed" unless by_id.fetch(political.id).fetch(:new_position) == 601
raise "Unlisted missing volume must fit reserved gap" unless by_id.fetch(missing_volume.id).fetch(:new_position) == 241
raise "Unknown categorized playlist must join political branch" unless (600...700).cover?(by_id.fetch(extra.id).fetch(:new_position))

begin
  planner.apply!(expected_fingerprint: "invalid")
  raise "Expected stale preview to be rejected"
rescue RuntimeError => e
  raise unless e.message.include?("changed since preview")
end

result = planner.apply!(expected_fingerprint: proposal.fetch(:fingerprint))
raise "Expected four changed positions" unless result.fetch(:changed) == 4
raise "Nil old position not preserved" unless UpdateLog.exists?(
  playlist_id: political.id, old_value: nil, change_summary: "playlist-position-reorder:#{result.fetch(:batch_id)}"
)
raise "Apply changed the wrong value" unless Playlist.find(missing_volume.id).position == 241

dub.update_columns(position: 199)
begin
  planner.rollback!(batch_id: result.fetch(:batch_id))
  raise "Expected conflicting rollback to be rejected"
rescue RuntimeError => e
  raise unless e.message.include?("changed since apply")
end
raise "Partial rollback occurred" unless Playlist.find(political.id).position == 601

dub.update_columns(position: 201)
count = planner.rollback!(batch_id: result.fetch(:batch_id))
raise "Rollback count unexpected" unless count == 4
raise "Old Dub position not restored" unless Playlist.find(dub.id).position == 8
raise "Old political nil not restored" unless Playlist.find(political.id).position.nil?
raise "Old future-volume position not restored" unless Playlist.find(missing_volume.id).position == 99
raise "Old additional position not restored" unless Playlist.find(extra.id).position == 45

puts "Playlist position preview, apply, and rollback smoke checks passed"
