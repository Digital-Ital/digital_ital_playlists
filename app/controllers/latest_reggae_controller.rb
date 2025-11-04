class LatestReggaeController < ApplicationController
  def index
    @featured_playlists = Playlist.featured.includes(:categories, :tracks).order(:position).limit(10)
  end
end

