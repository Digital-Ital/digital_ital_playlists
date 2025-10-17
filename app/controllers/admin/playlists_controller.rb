require 'net/http'
require 'json'

class Admin::PlaylistsController < Admin::BaseController
  before_action :set_playlist, only: [ :edit, :update, :destroy, :sync_with_spotify ]

  def index
    @categories = Category.ordered
    # Sort by followers count (popularity) by default, or by position/title
    @playlists = Playlist.includes(:categories)
                         .order(followers_count: :desc, position: :asc, title: :asc)
                         .page(params[:page])
                         .per(20)
    @uncategorized = Playlist.left_joins(:categories)
                             .where(categories: { id: nil })
                             .order(followers_count: :desc, position: :asc, title: :asc)
                             .page(params[:page])
                             .per(10)
  end

  def new
    @playlist = Playlist.new
  end

  def create
    @playlist = Playlist.new(playlist_params.except(:category_ids))
    if @playlist.save
      @playlist.category_ids = playlist_params[:category_ids] if playlist_params[:category_ids].present?
      redirect_to admin_playlists_path, notice: "Playlist created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @playlist.update(playlist_params.except(:category_ids))
      @playlist.category_ids = playlist_params[:category_ids] if playlist_params[:category_ids].present?
      redirect_to admin_playlists_path, notice: "Playlist updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @playlist.destroy
    redirect_to admin_playlists_path, notice: "Playlist deleted."
  end

  # POST /admin/playlists/import_spotify
  def import_spotify
    url = params[:spotify_url]
    if ENV["SPOTIFY_CLIENT_ID"].present? && ENV["SPOTIFY_CLIENT_SECRET"].present?
      importer = Spotify::PlaylistImporter.new(url)
      data = importer.call
      render json: data
    else
      importer = Spotify::OEmbedImporter.new(url)
      data = importer.call
      render json: data
    end
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /admin/playlists/:id/sync_with_spotify
  def sync_with_spotify
    result = PlaylistUpdateService.new(@playlist).call
    
    if result[:success]
      changes_count = result[:changes].size
      if changes_count > 0
        redirect_to admin_playlists_path, notice: "Playlist updated successfully! #{changes_count} changes detected."
      else
        redirect_to admin_playlists_path, notice: "Playlist is up to date. No changes detected."
      end
    else
      redirect_to admin_playlists_path, alert: "Failed to update playlist: #{result[:error]}"
    end
  end

  # GET /admin/playlists/batch_update_progress
  def batch_update_progress
    batch = BatchUpdate.active.first || BatchUpdate.recent.first
    
    if batch
      render json: {
        status: batch.status,
        current: batch.current_index || 0,
        total: batch.total_count,
        current_playlist: batch.current_playlist_title,
        completed: batch.status == 'completed',
        changes_count: batch.changes_count || 0
      }
    else
      render json: {
        status: 'idle',
        current: 0,
        total: 0,
        current_playlist: nil,
        completed: false,
        changes_count: 0
      }
    end
  end

  # POST /admin/playlists/start_batch_update
  def start_batch_update
    # Check if scheduler is paused (unless this is a forced update)
    if params[:force] != 'true' && SchedulerSetting.paused?
      render json: { success: false, status: 'paused', message: 'Scheduler is paused. Use force=true to override.' }, status: :ok and return
    end

    # If a batch is active and stale, fail it; otherwise block unless force=true
    if (active = BatchUpdate.active.first)
      stale_threshold_minutes = 20
      if params[:force] == 'true' || active.updated_at < stale_threshold_minutes.minutes.ago
        active.update!(status: 'failed')
      else
        render json: { success: false, status: 'running', message: 'Batch already running', batch_id: active.id }, status: :ok and return
      end
    end

    # Create a new batch update record
    batch = BatchUpdate.create!(
      status: 'running',
      current_index: 0,
      total_count: Playlist.count,
      changes_count: 0,
      started_at: Time.current
    )
    
    # Start the batch update in a thread (background)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          process_batch_update(batch.id)
        rescue => e
          Rails.logger.error "Batch update failed: #{e.message}\n#{e.backtrace.join("\n")}"
          batch.update!(status: 'failed')
        end
      end
    end
    
    render json: { success: true, total: Playlist.count, batch_id: batch.id }
  end

  private

  def process_batch_update(batch_id)
    batch = BatchUpdate.find(batch_id)
    playlists = Playlist.all.to_a  # Load all to avoid connection issues
    total_changes = 0
    skipped_count = 0
    
    # Get a single access token to reuse across all playlists
    access_token = fetch_spotify_token
    
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
        Rails.logger.error "Batch update failed for playlist #{playlist.id}: #{e.message}"
      end
      
      # Minimal delay to respect rate limits (0.5 seconds for skipped, 1 second for full sync)
      if result[:success] && result[:skipped]
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
    
    Rails.logger.info "Batch update completed: #{total_changes} changes, #{skipped_count} playlists skipped"
  rescue => e
    batch.update!(status: 'failed') if batch
    Rails.logger.error "Batch update process failed: #{e.message}"
  end
  
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

  def set_playlist
    @playlist = Playlist.find(params[:id])
  end

  def playlist_params
    params.require(:playlist).permit(:title, :description, :cover_image_url, :spotify_url, :track_count, :duration, :featured, :position, category_ids: [])
  end
end
