class Api::PlaylistsController < ApplicationController
  def index
    @playlists = Playlist.includes(:category).ordered
    if params[:category_ids].present?
      ids = params[:category_ids].to_s.split(",").map(&:to_i).uniq
      @playlists = @playlists.where(category_id: ids)
    end
    @playlists = @playlists.limit(20).offset(params[:offset] || 0)

    render json: {
      playlists: @playlists.map { |playlist| playlist_json(playlist) },
      has_more: @playlists.count == 20
    }
  end

  def by_category
    @category = Category.find(params[:id])
    ids = [ @category.id ] + @category.descendant_ids
    @playlists = Playlist.where(category_id: ids).ordered.limit(20).offset(params[:offset] || 0)

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
      category: {
        id: playlist.category.id,
        name: playlist.category.name,
        slug: playlist.category.slug,
        color: playlist.category.color
      }
    }
  end
end
