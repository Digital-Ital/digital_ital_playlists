namespace :playlists do
  desc "Update all playlists with optimized batch processing"
  task update_all: :environment do
    puts "Starting automated playlist update at #{Time.current}"
    
    # Create a batch update record
    batch = BatchUpdate.create!(
      status: 'running',
      current_index: 0,
      total_count: Playlist.count,
      changes_count: 0,
      started_at: Time.current
    )
    
    playlists = Playlist.all.to_a
    total_changes = 0
    skipped_count = 0
    
    # Get a single access token to reuse across all playlists
    access_token = fetch_spotify_token
    
    if access_token.nil?
      puts "ERROR: No Spotify API credentials configured"
      batch.update!(status: 'failed', ended_at: Time.current, failure_reason: 'No Spotify credentials')
      exit 1
    end
    
    playlists.each_with_index do |playlist, index|
      batch.update!(
        current_index: index + 1,
        current_playlist_title: playlist.title
      )
      
      begin
        result = PlaylistUpdateService.new(playlist).call_with_token(access_token)
        if result[:success]
          if result[:skipped]
            skipped_count += 1
            puts "Skipped #{playlist.title} (#{result[:reason]})"
          else
            total_changes += result[:changes].size
            batch.update!(changes_count: total_changes)
            puts "Updated #{playlist.title}: #{result[:changes].size} changes"
          end
        end
      rescue => e
        puts "ERROR: Failed to update playlist #{playlist.id}: #{e.message}"
        Rails.logger.error "Batch update failed for playlist #{playlist.id}: #{e.message}"
      end
      
      # Minimal delay to respect rate limits
      if result && result[:success] && result[:skipped]
        sleep(0.5) if index < playlists.size - 1  # Faster for skipped playlists
      else
        sleep(1) if index < playlists.size - 1   # Normal delay for full sync
      end
    end
    
    batch.update!(
      status: 'completed',
      completed_at: Time.current,
      changes_count: total_changes
    )
    
    puts "Batch update completed: #{total_changes} changes, #{skipped_count} playlists skipped"
    puts "Completed at #{Time.current}"
  end
  
  private
  
  def fetch_spotify_token
    return nil unless ENV["SPOTIFY_CLIENT_ID"].present? && ENV["SPOTIFY_CLIENT_SECRET"].present?
    
    uri = URI("https://accounts.spotify.com/api/token")
    req = Net::HTTP::Post.new(uri)
    req.set_form_data({ grant_type: "client_credentials" })
    req.basic_auth(ENV["SPOTIFY_CLIENT_ID"], ENV["SPOTIFY_CLIENT_SECRET"])
    
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.request(req)
    end
    
    return nil unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)["access_token"]
  end
end
