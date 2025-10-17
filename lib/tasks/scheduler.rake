require 'net/http'
require 'json'

namespace :scheduler do
  desc "Run scheduled playlist updates (respects pause/quick settings)"
  task update_playlists: :environment do
    # Check if scheduler is paused
    if SchedulerSetting.paused?
      puts "Scheduler is paused. Skipping update."
      exit 0
    end

    puts "Starting scheduled playlist update..."
    
    # Create a new batch update record
    batch = BatchUpdate.create!(
      status: 'running',
      current_index: 0,
      total_count: Playlist.count,
      changes_count: 0,
      started_at: Time.current,
      source: 'heroku_scheduler'
    )
    
    begin
      # Get a single access token to reuse across all playlists
      access_token = fetch_spotify_token
      
      playlists = Playlist.all.to_a
      total_changes = 0
      skipped_count = 0
      
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
              Rails.logger.info "Skipped #{playlist.title} (#{result[:reason]})"
            else
              total_changes += result[:changes].size
              batch.update!(changes_count: total_changes)
            end
          end
        rescue => e
          Rails.logger.error "Error updating #{playlist.title}: #{e.message}"
        end
      end
      
      batch.update!(
        status: 'completed',
        completed_at: Time.current,
        current_playlist_title: nil
      )
      
      puts "Batch update completed successfully. #{total_changes} changes made, #{skipped_count} playlists skipped."
      
    rescue => e
      Rails.logger.error "Batch update failed: #{e.message}\n#{e.backtrace.join("\n")}"
      batch.update!(
        status: 'failed',
        failure_reason: e.message,
        completed_at: Time.current
      )
      puts "Batch update failed: #{e.message}"
      exit 1
    end
  end
  
  private
  
  def fetch_spotify_token
    # This method should match the one in your playlists controller
    # You might want to extract this to a service class
    client_id = ENV['SPOTIFY_CLIENT_ID']
    client_secret = ENV['SPOTIFY_CLIENT_SECRET']
    
    uri = URI('https://accounts.spotify.com/api/token')
    req = Net::HTTP::Post.new(uri)
    req['Content-Type'] = 'application/x-www-form-urlencoded'
    req.body = "grant_type=client_credentials&client_id=#{client_id}&client_secret=#{client_secret}"
    
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.request(req)
    end
    
    raise "Spotify token error: #{res.code}" unless res.is_a?(Net::HTTPSuccess)
    
    JSON.parse(res.body)['access_token']
  end
end
