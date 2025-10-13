class PagesController < ApplicationController
  def home
    @categories = Category.roots.includes(children: :children)
    @main_families = Category.main_families.includes(children: :children)
    @featured_playlists = Playlist.featured.includes(:categories).order(:position).limit(4)
  end

  def whats_new
    @playlist_tracks = PlaylistTrack.includes(:track, playlist: :categories)
                                     .recent_additions
    
    # Filter by category if requested
    if params[:category_id].present?
      begin
        category = Category.find_by(id: params[:category_id])
        
        if category
          # Get all descendant category IDs
          category_ids = [ category.id ] + category.descendant_ids
          # Filter playlists that belong to any of these categories
          @playlist_tracks = @playlist_tracks.joins(:playlist)
                                             .joins("INNER JOIN playlist_categories ON playlist_categories.playlist_id = playlists.id")
                                             .where(playlist_categories: { category_id: category_ids })
                                             .distinct
        else
          # Invalid category ID - redirect to whats_new without filter
          redirect_to whats_new_path and return
        end
      rescue => e
        # Handle any other errors gracefully
        Rails.logger.error "Error filtering by category: #{e.message}"
        redirect_to whats_new_path and return
      end
    end
    
    @playlist_tracks = @playlist_tracks.page(params[:page]).per(50)
  end
end
