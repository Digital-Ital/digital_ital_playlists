class LatestReggaeController < ApplicationController
  def index
    @featured_playlists = Playlist.featured.includes(:categories, :tracks).order(created_at: :desc).limit(10)
  end
end

