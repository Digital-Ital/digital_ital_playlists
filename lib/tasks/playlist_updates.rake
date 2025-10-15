namespace :playlists do
  desc "Update all playlists with optimized batch processing"
  task update_all: :environment do
    start_time = Time.current
    puts "=" * 80
    puts "🎵 AUTOMATED PLAYLIST UPDATE STARTED"
    puts "=" * 80
    puts "⏰ Started at: #{start_time}"
    puts "📊 Total playlists: #{Playlist.count}"
    puts "🔧 Environment: #{Rails.env}"
    puts "=" * 80
    
    # Log to Rails logger as well
    Rails.logger.info "=" * 80
    Rails.logger.info "🎵 AUTOMATED PLAYLIST UPDATE STARTED"
    Rails.logger.info "=" * 80
    Rails.logger.info "⏰ Started at: #{start_time}"
    Rails.logger.info "📊 Total playlists: #{Playlist.count}"
    Rails.logger.info "🔧 Environment: #{Rails.env}"
    Rails.logger.info "=" * 80
    
    # Create a batch update record
    batch = BatchUpdate.create!(
      status: 'running',
      current_index: 0,
      total_count: Playlist.count,
      changes_count: 0,
      started_at: start_time,
      source: 'heroku_scheduler'
    )
    
    playlists = Playlist.all.to_a
    total_changes = 0
    skipped_count = 0
    error_count = 0
    updated_playlists = []
    skipped_playlists = []
    error_playlists = []
    
    # Get a single access token to reuse across all playlists
    access_token = fetch_spotify_token
    
    if access_token.nil?
      error_msg = "ERROR: No Spotify API credentials configured"
      puts error_msg
      Rails.logger.error error_msg
      batch.update!(status: 'failed', ended_at: Time.current, failure_reason: 'No Spotify credentials')
      exit 1
    end
    
    puts "🔑 Spotify token obtained successfully"
    Rails.logger.info "🔑 Spotify token obtained successfully"
    
    playlists.each_with_index do |playlist, index|
      current_time = Time.current
      progress = "#{index + 1}/#{playlists.size}"
      
      batch.update!(
        current_index: index + 1,
        current_playlist_title: playlist.title
      )
      
      begin
        result = PlaylistUpdateService.new(playlist).call_with_token(access_token)
        if result[:success]
          if result[:skipped]
            skipped_count += 1
            skipped_playlists << playlist.title
            log_msg = "⏭️  [#{progress}] Skipped: #{playlist.title} (#{result[:reason]})"
            puts log_msg
            Rails.logger.info log_msg
          else
            total_changes += result[:changes].size
            updated_playlists << { title: playlist.title, changes: result[:changes].size }
            batch.update!(changes_count: total_changes)
            log_msg = "✅ [#{progress}] Updated: #{playlist.title} (#{result[:changes].size} changes)"
            puts log_msg
            Rails.logger.info log_msg
            
            # Log individual changes
            result[:changes].each do |change|
              change_msg = "   📝 #{change[:type]}: #{change[:field] || change[:track]&.name || 'N/A'}"
              puts change_msg
              Rails.logger.info change_msg
            end
          end
        else
          error_count += 1
          error_playlists << playlist.title
          error_msg = "❌ [#{progress}] Failed: #{playlist.title} - #{result[:error]}"
          puts error_msg
          Rails.logger.error error_msg
        end
      rescue => e
        error_count += 1
        error_playlists << playlist.title
        error_msg = "💥 [#{progress}] Error: #{playlist.title} - #{e.message}"
        puts error_msg
        Rails.logger.error "Batch update failed for playlist #{playlist.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
      
      # Minimal delay to respect rate limits
      if result && result[:success] && result[:skipped]
        sleep(0.5) if index < playlists.size - 1  # Faster for skipped playlists
      else
        sleep(1) if index < playlists.size - 1   # Normal delay for full sync
      end
    end
    
    end_time = Time.current
    duration = (end_time - start_time).round(2)
    
    batch.update!(
      status: 'completed',
      completed_at: end_time,
      changes_count: total_changes
    )
    
    # Final summary
    puts "=" * 80
    puts "🎵 AUTOMATED PLAYLIST UPDATE COMPLETED"
    puts "=" * 80
    puts "⏰ Started: #{start_time}"
    puts "⏰ Ended: #{end_time}"
    puts "⏱️  Duration: #{duration} seconds"
    puts "📊 Results:"
    puts "   ✅ Updated: #{updated_playlists.size} playlists"
    puts "   ⏭️  Skipped: #{skipped_count} playlists"
    puts "   ❌ Errors: #{error_count} playlists"
    puts "   🔄 Total changes: #{total_changes}"
    puts "=" * 80
    
    if updated_playlists.any?
      puts "📝 Updated playlists:"
      updated_playlists.each do |playlist|
        puts "   • #{playlist[:title]} (#{playlist[:changes]} changes)"
      end
      puts "=" * 80
    end
    
    if error_playlists.any?
      puts "❌ Failed playlists:"
      error_playlists.each do |playlist|
        puts "   • #{playlist}"
      end
      puts "=" * 80
    end
    
    # Log to Rails logger as well
    Rails.logger.info "=" * 80
    Rails.logger.info "🎵 AUTOMATED PLAYLIST UPDATE COMPLETED"
    Rails.logger.info "=" * 80
    Rails.logger.info "⏰ Started: #{start_time}"
    Rails.logger.info "⏰ Ended: #{end_time}"
    Rails.logger.info "⏱️  Duration: #{duration} seconds"
    Rails.logger.info "📊 Results:"
    Rails.logger.info "   ✅ Updated: #{updated_playlists.size} playlists"
    Rails.logger.info "   ⏭️  Skipped: #{skipped_count} playlists"
    Rails.logger.info "   ❌ Errors: #{error_count} playlists"
    Rails.logger.info "   🔄 Total changes: #{total_changes}"
    Rails.logger.info "=" * 80
    
    if updated_playlists.any?
      Rails.logger.info "📝 Updated playlists:"
      updated_playlists.each do |playlist|
        Rails.logger.info "   • #{playlist[:title]} (#{playlist[:changes]} changes)"
      end
      Rails.logger.info "=" * 80
    end
    
    if error_playlists.any?
      Rails.logger.info "❌ Failed playlists:"
      error_playlists.each do |playlist|
        Rails.logger.info "   • #{playlist}"
      end
      Rails.logger.info "=" * 80
    end
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
