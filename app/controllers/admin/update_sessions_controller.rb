class Admin::UpdateSessionsController < Admin::BaseController
  before_action :set_update_session, only: [:show, :destroy, :apply_changes]

  def index
    @update_sessions = UpdateSession.recent.includes(:playlist_updates).page(params[:page]).per(20)
  end

  def show
    @playlist_updates = @update_session.playlist_updates.includes(:playlist).order(:created_at)
    @updates_by_playlist = @playlist_updates.group_by(&:playlist)
  end

  def new
    # This will start a new update session
    @update_session = UpdateSession.new
  end

  def create
    @update_session = UpdateSession.create!(
      started_at: Time.current,
      status: 'running',
      total_playlists: Playlist.count
    )

    # Run the update process immediately (synchronous for Heroku)
    begin
      updated_count = 0
      processed_count = 0
      
      Rails.logger.info "Starting update session #{@update_session.id} for #{Playlist.count} playlists"
      
      Playlist.find_each do |playlist|
        processed_count += 1
        Rails.logger.info "Processing playlist #{processed_count}/#{Playlist.count}: #{playlist.title} (ID: #{playlist.spotify_id})"
        
        spotify_data = fetch_playlist_data(playlist.spotify_id)
        
        if spotify_data
          Rails.logger.info "Fetched data for #{playlist.title}: #{spotify_data.keys}"
          # Check for changes in each field
          check_field_change(playlist, @update_session, 'title', playlist.title, spotify_data[:title])
          check_field_change(playlist, @update_session, 'track_count', playlist.track_count, spotify_data[:track_count])
          check_field_change(playlist, @update_session, 'duration', playlist.duration, spotify_data[:duration])
          check_field_change(playlist, @update_session, 'description', playlist.description, spotify_data[:description])
          check_field_change(playlist, @update_session, 'cover_image_url', playlist.cover_image_url, spotify_data[:cover_image_url])
          
          updated_count += 1 if any_changes?(playlist, spotify_data)
        else
          Rails.logger.warn "Failed to fetch data for #{playlist.title}"
          # Create update record for failed fetch
          PlaylistUpdate.create!(
            update_session: @update_session,
            playlist: playlist,
            field_name: 'fetch_error',
            old_value: 'success',
            new_value: 'failed',
            status: 'pending'
          )
        end
      end
      
      Rails.logger.info "Update session #{@update_session.id} completed: #{updated_count} playlists with changes, #{@update_session.playlist_updates.count} total updates"
      
      @update_session.update!(
        status: 'completed',
        completed_at: Time.current,
        updated_playlists: updated_count
      )
      
    rescue => e
      @update_session.update!(
        status: 'failed',
        completed_at: Time.current
      )
      Rails.logger.error "Update session failed: #{e.message}"
    end

    redirect_to admin_update_session_path(@update_session), 
                notice: "Update session completed! Found #{@update_session.playlist_updates.count} changes."
  end

  def apply_changes
    @playlist_updates = @update_session.playlist_updates.pending.includes(:playlist)
    
    if params[:confirm_all] == 'true'
      # Apply all pending changes
      @playlist_updates.each do |update|
        apply_single_change(update)
      end
      @update_session.update!(status: 'completed', completed_at: Time.current)
      redirect_to admin_update_session_path(@update_session), 
                  notice: "All changes applied successfully!"
    else
      # Show confirmation page
      render :confirm_changes
    end
  end

  def destroy
    @update_session.destroy
    redirect_to admin_update_sessions_path, notice: "Update session deleted."
  end

  private

  def set_update_session
    @update_session = UpdateSession.find(params[:id])
  end

  def apply_single_change(update)
    playlist = update.playlist
    case update.field_name
    when 'title'
      playlist.update!(title: update.new_value)
    when 'track_count'
      playlist.update!(track_count: update.new_value.to_i)
    when 'duration'
      playlist.update!(duration: update.new_value)
    when 'description'
      playlist.update!(description: update.new_value)
    when 'cover_image_url'
      playlist.update!(cover_image_url: update.new_value)
    end
    update.update!(status: 'applied')
  end

  def fetch_playlist_data(spotify_id)
    return nil unless spotify_id.present?

    # Use your existing Spotify service with the full URL
    spotify_url = "https://open.spotify.com/playlist/#{spotify_id}"
    
    # Check if we have Spotify API credentials
    if ENV["SPOTIFY_CLIENT_ID"].present? && ENV["SPOTIFY_CLIENT_SECRET"].present?
      spotify_service = Spotify::PlaylistImporter.new(spotify_url)
      spotify_service.call
    else
      # Fallback to oEmbed if no API credentials
      spotify_service = Spotify::OEmbedImporter.new(spotify_url)
      data = spotify_service.call
      # Convert oEmbed format to our expected format
      {
        title: data[:title],
        description: nil, # oEmbed doesn't provide description
        cover_image_url: data[:thumbnail_url],
        track_count: nil, # oEmbed doesn't provide track count
        duration: nil, # oEmbed doesn't provide duration
        spotify_url: spotify_url
      }
    end
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
