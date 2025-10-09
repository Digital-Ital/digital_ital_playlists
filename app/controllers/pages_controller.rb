class PagesController < ApplicationController
  def home
    @categories = Category.roots.includes(children: :children)
    @main_families = Category.main_families.includes(children: :children)
  end

  def whats_new
    @playlist_tracks = PlaylistTrack.includes(:track, playlist: :categories)
                                     .recent_additions
    
    # Filter by category if requested
    if params[:category_id].present?
      category = Category.find(params[:category_id])
      # Get all descendant category IDs
      category_ids = [ category.id ] + category.descendant_ids
      # Filter playlists that belong to any of these categories
      @playlist_tracks = @playlist_tracks.joins(:playlist)
                                         .joins("INNER JOIN playlist_categories ON playlist_categories.playlist_id = playlists.id")
                                         .where(playlist_categories: { category_id: category_ids })
                                         .distinct
    end
    
    @playlist_tracks = @playlist_tracks.page(params[:page]).per(50)
  end
end
