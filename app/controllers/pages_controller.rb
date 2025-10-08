class PagesController < ApplicationController
  def home
    @categories = Category.roots.includes(children: :children)
    @main_families = Category.main_families.includes(children: :children)
  end

  def whats_new
    @playlist_tracks = PlaylistTrack.includes(:track, :playlist)
                                     .recent_additions
                                     .page(params[:page])
                                     .per(50)
  end
end
