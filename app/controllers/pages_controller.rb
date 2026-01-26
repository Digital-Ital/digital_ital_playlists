class PagesController < ApplicationController
  def home
    @categories = Category.roots.includes(children: { children: :playlists })
    @main_families = Category.main_families.includes(children: { children: :playlists })
    @total_playlists_count = Playlist.count
    @total_followers_count = Playlist.sum(:followers_count)
  end

  def whats_new
    # Get all recent playlist tracks
    playlist_tracks = PlaylistTrack.includes(:track, playlist: :categories)
                                   .recent_additions

    # Filter by category if requested
    if params[:category_id].present?
      begin
        category = Category.find_by(id: params[:category_id])

        if category
          # Get all descendant category IDs
          category_ids = [ category.id ] + category.descendant_ids
          # Filter playlists that belong to any of these categories
          playlist_tracks = playlist_tracks.joins(:playlist)
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

    # Group tracks by song and create grouped data structure
    @grouped_tracks = group_tracks_by_song(playlist_tracks)

    # Calculate total HOT songs count across all pages (before filtering)
    @total_hot_songs_count = @grouped_tracks.count { |group| group[:total_playlists] >= 3 }

    # Filter for HOT songs only if requested
    if params[:hot_only] == "true"
      @grouped_tracks = @grouped_tracks.select { |group| group[:total_playlists] >= 3 }
    end

    # Apply pagination to the grouped results
    @grouped_tracks = Kaminari.paginate_array(@grouped_tracks).page(params[:page]).per(50)
  end

  def all_songs
    @playlists = Playlist.ordered
    @selected_playlist_ids = normalize_playlist_ids(params[:playlist_ids])
    @filter_mode = params[:filter_mode] == "and" ? "and" : "or"
    @sort = normalize_sort_param(params[:sort])
    @query = params[:query].to_s.strip

    playlist_tracks = PlaylistTrack.includes(:track, playlist: :categories)

    if @selected_playlist_ids.any?
      if @filter_mode == "and"
        track_ids = PlaylistTrack.where(playlist_id: @selected_playlist_ids)
                                 .group(:track_id)
                                 .having("COUNT(DISTINCT playlist_id) = ?", @selected_playlist_ids.size)
                                 .pluck(:track_id)
        playlist_tracks = playlist_tracks.where(track_id: track_ids)
      else
        playlist_tracks = playlist_tracks.where(playlist_id: @selected_playlist_ids)
      end
    end

    if @query.present?
      query_value = "%#{@query.downcase}%"
      playlist_tracks = playlist_tracks.joins(:track).where(
        "LOWER(tracks.name) LIKE :query OR LOWER(tracks.artist) LIKE :query OR LOWER(tracks.album) LIKE :query",
        query: query_value
      )
    end

    @grouped_tracks = group_tracks_for_all_songs(playlist_tracks, sort_by: @sort)
    @grouped_tracks = Kaminari.paginate_array(@grouped_tracks).page(params[:page]).per(50)
  end

  private

  def group_tracks_by_song(playlist_tracks)
    # Group by track_id and collect all playlist tracks for each song
    grouped = playlist_tracks.group_by(&:track_id)

    # Transform into array of grouped track data
    grouped.map do |track_id, tracks|
      # Sort tracks by added_at (most recent first)
      sorted_tracks = tracks.sort_by { |t| -t.added_at.to_i }

      # Get the most recent playlist track (main card)
      main_track = sorted_tracks.first

      # Get all other playlist tracks (also added to)
      other_tracks = sorted_tracks[1..-1] || []

      # Collect all unique categories from all playlists this song appears in
      # Sort them the same way as the home screen: main families first, then by position, then by name
      all_categories = tracks.flat_map { |t| t.playlist.categories }.uniq.sort_by do |category|
        # Main families first (is_main_family = true)
        main_family_priority = category.is_main_family? ? 0 : 1

        # Then by display_order or position (NULLS LAST)
        display_order = category.display_order || category.position || 999999

        # Then by name
        [ main_family_priority, display_order, category.name ]
      end

      {
        track: main_track.track,
        main_playlist_track: main_track,
        other_playlist_tracks: other_tracks,
        total_playlists: tracks.count,
        all_categories: all_categories
      }
    end.sort_by { |group| -group[:main_playlist_track].added_at.to_i }
  end

  def group_tracks_for_all_songs(playlist_tracks, sort_by:)
    grouped = playlist_tracks.group_by(&:track_id)

    groups = grouped.map do |track_id, tracks|
      sorted_tracks = tracks.sort_by { |t| -t.added_at.to_i }
      main_track = sorted_tracks.first
      playlists = tracks.map(&:playlist).uniq { |playlist| playlist.id }
      categories = playlists.flat_map(&:categories).uniq { |category| category.id }

      {
        track: main_track.track,
        playlist_tracks: sorted_tracks,
        playlists: playlists,
        total_playlists: playlists.count,
        last_added_at: main_track.added_at,
        categories: categories
      }
    end

    case sort_by
    when "artist"
      groups.sort_by { |group| [ group[:track].artist.to_s.downcase, group[:track].name.to_s.downcase ] }
    when "title"
      groups.sort_by { |group| [ group[:track].name.to_s.downcase, group[:track].artist.to_s.downcase ] }
    when "playlist_count"
      groups.sort_by { |group| [ -group[:total_playlists], group[:track].name.to_s.downcase ] }
    else
      groups.sort_by { |group| -group[:last_added_at].to_i }
    end
  end

  def normalize_playlist_ids(raw_ids)
    ids = if raw_ids.is_a?(Array)
      raw_ids
    else
      raw_ids.to_s.split(",")
    end

    ids.map { |id| id.to_s.strip }.reject(&:blank?).map(&:to_i).uniq
  end

  def normalize_sort_param(sort_param)
    sort = sort_param.to_s
    %w[recent artist title playlist_count].include?(sort) ? sort : "recent"
  end
end
