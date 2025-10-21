class PagesController < ApplicationController
  def home
    @categories = Category.roots.includes(children: { children: :playlists })
    @main_families = Category.main_families.includes(children: { children: :playlists })
    @featured_playlists = Playlist.featured.includes(:categories).order(:position).limit(8)
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
end
