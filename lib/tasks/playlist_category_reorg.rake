# frozen_string_literal: true

namespace :playlist_categories do
  desc "Preview all 66 curator-approved changes without writing to the database"
  task preview: :environment do
    proposal = PlaylistCategoryReorganization.new.preview
    puts "APPROVED CATEGORY AUDIT — READ-ONLY PREVIEW"
    puts "Validated original 110-playlist inventory: #{proposal.fetch(:inventory_sha256)}"
    puts "Affected playlists: #{proposal.fetch(:changes).length}"
    puts "Category additions: #{proposal.fetch(:additions)}"
    puts "Category removals: #{proposal.fetch(:removals)}"
    puts "Rename: #{proposal.fetch(:rename_from)} => #{proposal.fetch(:rename_to)}"
    puts "Original category URL slug will remain: #{proposal.fetch(:category_slug)}"
    proposal.fetch(:changes).each do |row|
      puts "##{row.fetch(:id)} (position #{row.fetch(:position)}): #{row.fetch(:title)}"
      puts "  + #{row.fetch(:add).join(', ')}" if row.fetch(:add).any?
      puts "  - #{row.fetch(:remove).join(', ')}" if row.fetch(:remove).any?
    end
    puts "Read-only preview completed. No changes have been made."
  end

  desc "Apply ALL approved additions, removals and the rename in one reversible transaction"
  task apply: :environment do
    abort "Set CONFIRM=APPLY_APPROVED_66" unless ENV["CONFIRM"] == "APPLY_APPROVED_66"

    result = PlaylistCategoryReorganization.new.apply!
    puts "SUCCESS: all approved category changes committed."
    puts "Playlists updated: #{result.fetch(:playlists_changed)}"
    puts "Membership additions: #{result.fetch(:additions)}"
    puts "Membership removals: #{result.fetch(:removals)}"
    puts "Category renamed: #{result.fetch(:category_renamed)}"
    puts "ROLLBACK_BATCH=#{result.fetch(:batch_id)}"
    puts "Copy the batch ID if you may need to restore the previous assignments."
  end

  desc "Restore all modified memberships and the category name from a saved batch"
  task rollback: :environment do
    abort "Set CONFIRM=ROLLBACK_APPROVED_CATEGORIES and BATCH=<batch id>" unless ENV["CONFIRM"] == "ROLLBACK_APPROVED_CATEGORIES" && ENV["BATCH"].present?

    count = PlaylistCategoryReorganization.new.rollback!(batch_id: ENV.fetch("BATCH"))
    puts "SUCCESS: restored original memberships for #{count} playlists and restored the category name."
  end
end
