class Admin::PlaylistsController < Admin::BaseController
  before_action :set_playlist, only: [ :edit, :update, :destroy, :sync_with_spotify ]

  def index
    @categories = Category.ordered
    @playlists = Playlist.includes(:categories).ordered.page(params[:page]).per(20)
    @uncategorized = Playlist.left_joins(:categories).where(categories: { id: nil }).ordered.page(params[:page]).per(10)
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

  private

  def set_playlist
    @playlist = Playlist.find(params[:id])
  end

  def playlist_params
    params.require(:playlist).permit(:title, :description, :cover_image_url, :spotify_url, :track_count, :duration, :featured, :position, category_ids: [])
  end
end
