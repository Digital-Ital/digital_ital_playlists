namespace :production do
  desc "Clear all production data for fresh start"
  task clear_all_data: :environment do
    if Rails.env.production?
      puts "🗑️  Clearing all Digital Ital production data for fresh start..."
      puts ""

      # Show current stats
      puts "📊 Current production data:"
      puts "   - #{Category.count} categories"
      puts "   - #{Playlist.count} playlists"
      puts "   - #{ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM playlist_categories").first[0]} playlist-category associations"
      puts ""

      # Delete in correct order to avoid foreign key constraints
      puts "🗑️  Deleting playlist-category associations..."
      ActiveRecord::Base.connection.execute("DELETE FROM playlist_categories")

      puts "🗑️  Deleting all playlists..."
      Playlist.delete_all

      puts "🗑️  Deleting all categories..."
      Category.delete_all

      puts ""
      puts "✅ All production data cleared!"
      puts ""
      puts "📊 New stats:"
      puts "   - #{Category.count} categories"
      puts "   - #{Playlist.count} playlists"
      puts "   - #{ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM playlist_categories").first[0]} playlist-category associations"
      puts ""
      puts "🎵 Production site ready for fresh start!"
    else
      puts "❌ This task can only be run in production environment"
      puts "   Current environment: #{Rails.env}"
    end
  end
end
