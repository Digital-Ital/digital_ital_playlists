# frozen_string_literal: true

namespace :playlist_positions do
  desc "Read-only inventory of playlist IDs, titles, existing positions, and categories"
  task inventory: :environment do
    Playlist.includes(:categories).order(:id).each do |playlist|
      puts JSON.generate(
        id: playlist.id, title: playlist.title, position: playlist.position,
        categories: playlist.categories.map(&:name).sort
      )
    end
  end

  desc "Preview branch order, including reserved empty slots (no database writes)"
  task preview: :environment do
    planner = PlaylistPositionReorganization.new
    proposal = planner.plan
    entries = proposal.fetch(:entries)
    puts "PLAYLIST POSITION REORGANIZATION — DRY RUN"
    puts "PLAYLIST COUNT: #{entries.size}"
    puts "PREVIEW_SHA=#{proposal.fetch(:fingerprint)}"
    puts "Matching curated directory: #{entries.count { |item| item[ :match ] == 'manifest' }}"
    puts "Additional playlists (inferred branch; review these): #{entries.count { |item| item[ :match ] == 'inferred' }}"
    puts "Changes proposed: #{entries.count { |item| item[ :old_position ] != item[ :new_position ] }}"
    puts "Rows: new_position | old_position | ID | match | title"
    entries.each do |item|
      puts "%3d | %4s | %5d | %8s | %s" % [
        item.fetch(:new_position),
        item[ :old_position ].nil? ? "-" : item[ :old_position ],
        item.fetch(:id), item.fetch(:match), item.fetch(:title)
      ]
    end
    puts ""
    puts "The 110-title directory reserves positions even for titles not yet in the DB."
    puts "REVIEW FIRST. To apply, run with PREVIEW_SHA=<hash above> CONFIRM=REORDER_8_BRANCHES."
    puts "Rollback batch ID will be printed and stored with before/after values in UpdateLog."
  end

  desc "Apply previewed positions only, atomically; write persistent per-playlist rollback logs"
  task apply: :environment do
    abort "Set CONFIRM=REORDER_8_BRANCHES" unless ENV["CONFIRM"] == "REORDER_8_BRANCHES"
    abort "Set PREVIEW_SHA to the exact hash from preview" if ENV["PREVIEW_SHA"].to_s.empty?

    result = PlaylistPositionReorganization.new.apply!(expected_fingerprint: ENV.fetch("PREVIEW_SHA"))
    puts "SUCCESS: #{result.fetch(:changed)} playlist positions updated."
    puts "ROLLBACK_BATCH=#{result.fetch(:batch_id)}"
    puts "Keep this batch ID. Rollback records are stored in the database's existing UpdateLog table."
  end

  desc "Restore all positions changed by a batch; refuse if any position has since changed"
  task rollback: :environment do
    abort "Set CONFIRM=ROLLBACK_POSITIONS and BATCH=<batch ID>" unless ENV["CONFIRM"] == "ROLLBACK_POSITIONS"
    count = PlaylistPositionReorganization.new.rollback!(batch_id: ENV["BATCH"])
    puts "SUCCESS: restored #{count} previous playlist positions."
  end
end
