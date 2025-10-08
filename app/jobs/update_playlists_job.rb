class UpdatePlaylistsJob < ApplicationJob
  queue_as :default

  def perform(update_session_id)
    update_session = UpdateSession.find(update_session_id)
    updated_count = 0
    
    begin
      Playlist.find_each do |playlist|
        spotify_data = fetch_playlist_data(playlist.spotify_id)
        
        if spotify_data
          # Check for changes in each field
          check_field_change(playlist, update_session, 'title', playlist.title, spotify_data[:title])
          check_field_change(playlist, update_session, 'track_count', playlist.track_count, spotify_data[:track_count])
          check_field_change(playlist, update_session, 'duration', playlist.duration, spotify_data[:duration])
          check_field_change(playlist, update_session, 'description', playlist.description, spotify_data[:description])
          check_field_change(playlist, update_session, 'cover_image_url', playlist.cover_image_url, spotify_data[:cover_image_url])
          
          updated_count += 1 if any_changes?(playlist, spotify_data)
        else
          # Create update record for failed fetch
          PlaylistUpdate.create!(
            update_session: update_session,
            playlist: playlist,
            field_name: 'fetch_error',
            old_value: 'success',
            new_value: 'failed',
            status: 'pending'
          )
        end
      end
      
      update_session.update!(
        status: 'completed',
        completed_at: Time.current,
        updated_playlists: updated_count
      )
      
    rescue => e
      update_session.update!(
        status: 'failed',
        completed_at: Time.current
      )
      Rails.logger.error "Update session failed: #{e.message}"
    end
  end

  private

  def fetch_playlist_data(spotify_id)
    return nil unless spotify_id.present?

    # Use your existing Spotify service
    spotify_service = Spotify::PlaylistImporter.new("https://open.spotify.com/playlist/#{spotify_id}")
    spotify_service.call
  rescue => e
    Rails.logger.error "Failed to fetch Spotify data for #{spotify_id}: #{e.message}"
    nil
  end

  def check_field_change(playlist, update_session, field_name, old_value, new_value)
    return if old_value.to_s == new_value.to_s

    PlaylistUpdate.create!(
      update_session: update_session,
      playlist: playlist,
      field_name: field_name,
      old_value: old_value.to_s,
      new_value: new_value.to_s,
      status: 'pending'
    )
  end

  def any_changes?(playlist, spotify_data)
    playlist.title != spotify_data[:title] ||
    playlist.track_count != spotify_data[:track_count] ||
    playlist.duration != spotify_data[:duration] ||
    playlist.description != spotify_data[:description] ||
    playlist.cover_image_url != spotify_data[:cover_image_url]
  end
end
