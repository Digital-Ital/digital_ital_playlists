class PagesController < ApplicationController
  def home
    @featured_playlists = Playlist.featured.ordered.limit(4)
    @categories = Category.roots.includes(children: :children)
    @main_families = Category.main_families.includes(children: :children)
  end
end
