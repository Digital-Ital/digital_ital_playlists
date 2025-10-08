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

    # Start the update process in background
    UpdatePlaylistsJob.perform_later(@update_session.id)

    redirect_to admin_update_session_path(@update_session), 
                notice: "Update session started! Checking all playlists..."
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
end
