class Admin::PlaylistsController < Admin::BaseController
  before_action :set_playlist, only: [:show, :edit, :update, :destroy]

  def index
    @categories = Category.ordered
    @playlists = Playlist.includes(:category).ordered
    @uncategorized = Playlist.where(category_id: nil).ordered
  end

  def new
    @playlist = Playlist.new
  end

  def create
    @playlist = Playlist.new(playlist_params)
    if @playlist.save
      redirect_to admin_playlists_path, notice: 'Playlist created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @playlist.update(playlist_params)
      redirect_to admin_playlists_path, notice: 'Playlist updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @playlist.destroy
    redirect_to admin_playlists_path, notice: 'Playlist deleted.'
  end

  # POST /admin/playlists/import_spotify
  def import_spotify
    importer = Spotify::OEmbedImporter.new(params[:spotify_url])
    data = importer.call
    render json: data
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_playlist
    @playlist = Playlist.find(params[:id])
  end

  def playlist_params
    params.require(:playlist).permit(:title, :description, :cover_image_url, :spotify_url, :track_count, :duration, :category_id, :featured, :position)
  end
end


