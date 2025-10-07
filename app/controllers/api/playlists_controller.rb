class Api::PlaylistsController < ApplicationController
  protect_from_forgery with: :null_session
  def index
    @playlists = Playlist.includes(:categories).ordered.distinct
    if params[:category_ids].present?
      ids = params[:category_ids].to_s.split(",").map(&:to_i).uniq
      @playlists = @playlists.by_category_ids(ids)
    end
    @playlists = @playlists.limit(20).offset(params[:offset] || 0)

    render json: {
      playlists: @playlists.map { |playlist| playlist_json(playlist) },
      has_more: @playlists.count == 20
    }
  end

  def by_category
    begin
      @category = Category.find(params[:id])
      ids = [ @category.id ] + @category.descendant_ids
      # Ensure playlists appear if they belong to ANY of the selected categories,
      # even when they are assigned to multiple categories across branches.
      @playlists = Playlist
        .joins(:categories)
        .where(playlist_categories: { category_id: ids })
        .includes(:categories)
        .distinct
        .ordered
        .limit(20)
        .offset((params[:offset] || 0).to_i)

      render json: {
        category: {
          id: @category.id,
          name: @category.name,
          slug: @category.slug,
          color: @category.color
        },
        playlists: @playlists.map { |playlist| playlist_json(playlist) },
        has_more: @playlists.count == 20
      }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Category not found" }, status: :not_found
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
      categories: playlist.categories.flat_map do |category|
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
