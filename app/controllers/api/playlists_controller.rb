class Api::PlaylistsController < ApplicationController
  protect_from_forgery with: :null_session
  def index
    # Return ALL playlists when all=true (no pagination)
    if params[:all].to_s == 'true'
      scope = Playlist.left_joins(:categories).includes(:categories).distinct.ordered
      if params[:category_ids].present?
        ids = params[:category_ids].to_s.split(",").map(&:to_i).uniq.compact
        # Only filter if we have valid category IDs
        if ids.any?
          scope = Playlist.by_category_ids(ids).includes(:categories).ordered
        end
      end
      playlists = scope.to_a
      render json: { playlists: playlists.map { |p| playlist_json(p) }, has_more: false }
      return
    end

    per_page = [[params[:per_page].to_i, 1].max, 100].min rescue 30
    per_page = 30 if per_page.zero?
    offset = (params[:offset] || 0).to_i

    # Use left_joins to include playlists even if they have no categories
    scope = Playlist.left_joins(:categories).includes(:categories)
    
    # Search filter (case-insensitive)
    if params[:search].present?
      search_term = "%#{params[:search].downcase}%"
      scope = scope.where("LOWER(playlists.title) LIKE ? OR LOWER(playlists.description) LIKE ?", search_term, search_term)
    end
    
    # Ensure distinct playlists (important when joined with categories)
    scope = scope.distinct
    
    if params[:category_ids].present?
      ids = params[:category_ids].to_s.split(",").map(&:to_i).uniq.compact
      # Only filter if we have valid category IDs
      if ids.any?
        scope = Playlist.by_category_ids(ids).includes(:categories) # ensures correct join semantics
      end
    end
    scope = scope.ordered

    records = scope.offset(offset).limit(per_page + 1).to_a
    has_more = records.length > per_page
    page_records = records.first(per_page)

    render json: {
      playlists: page_records.map { |playlist| playlist_json(playlist) },
      has_more: has_more
    }
  end

  def by_category
    begin
      @category = Category.find(params[:id])
      ids = [ @category.id ] + @category.descendant_ids
      per_page = [[params[:per_page].to_i, 1].max, 100].min rescue 20
      per_page = 20 if per_page.zero?
      offset = (params[:offset] || 0).to_i

      scope = Playlist
        .joins(:categories)
        .where(playlist_categories: { category_id: ids })
        .includes(:categories)
        .distinct
        .ordered

      records = scope.offset(offset).limit(per_page + 1).to_a
      has_more = records.length > per_page
      page_records = records.first(per_page)

      render json: {
        category: {
          id: @category.id,
          name: @category.name,
          slug: @category.slug,
          color: @category.color
        },
        playlists: page_records.map { |playlist| playlist_json(playlist) },
        has_more: has_more
      }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Category not found" }, status: :not_found
    end
  end
  
  def random_track
    # Get a random track from all playlists
    random_track = Track.joins(:playlist_tracks)
                       .where.not(external_url: nil)
                       .order("RANDOM()")
                       .limit(1)
                       .first
    
    if random_track
      # Get the playlist this track is in (pick first if in multiple)
      playlist = random_track.playlists.first
      
      render json: {
        track: {
          id: random_track.id,
          name: random_track.name,
          artist: random_track.artist,
          album: random_track.album,
          image_url: random_track.image_url,
          external_url: random_track.external_url
        },
        playlist: {
          id: playlist.id,
          title: playlist.title,
          spotify_url: playlist.spotify_url
        }
      }
    else
      render json: { error: "No tracks found" }, status: :not_found
    end
  end

  private

  def playlist_json(playlist)
    {
      id: playlist.id,
      title: playlist.title,
      description: playlist.description,
      cover_image_url: playlist.cover_image_url,
      spotify_url: playlist.spotify_url,
      track_count: playlist.track_count,
      duration: playlist.duration_formatted,
      reaction_count: playlist.reaction_count || 0,
      categories: playlist.categories.reload.flat_map do |category|
        # Include the category itself and all its parent categories
        categories_to_show = [category]
        current = category.parent
        while current
          categories_to_show << current
          current = current.parent
        end
        
        categories_to_show.map do |cat|
          {
            id: cat.id,
            name: cat.name,
            slug: cat.slug,
            color: cat.color,
            is_root: cat.parent_id.nil?
          }
        end
      end.uniq { |cat| cat[:id] }
    }
  end
end
