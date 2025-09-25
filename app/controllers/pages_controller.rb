class PagesController < ApplicationController
  def home
    @featured_playlists = Playlist.featured.ordered.limit(4)
    @categories = Category.roots.includes(children: :children)
  end
end
