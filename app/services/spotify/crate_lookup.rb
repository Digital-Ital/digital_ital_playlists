module Spotify
  class CrateLookup
    DURATION_TOLERANCE_MS = 12_000

    def self.from_spotify(track)
      new(track).result
    end

    def self.footprint_for(track, scope:)
      new(track).footprint(scope)
    end

    def self.from_local_track(track)
      new(
        spotify_id: track.spotify_id,
        name: track.name,
        artist: track.artist,
        album: track.album,
        image_url: track.image_url,
        external_url: track.external_url,
        duration_ms: track.duration_ms
      ).result(local_tracks: [ track ], match_type: :exact)
    end

    def self.search(query, limit: 30)
      tokens = query.to_s.downcase.split(/\s+/).reject(&:blank?).first(5)
      return [] if tokens.empty?

      scope = Track.all
      tokens.each do |token|
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(token)}%"
        scope = scope.where(
          "LOWER(name) LIKE ? OR LOWER(artist) LIKE ? OR LOWER(album) LIKE ?",
          pattern, pattern, pattern
        )
      end

      scope.order(:artist, :name).limit(limit)
    end

    def initialize(track)
      @track = track.symbolize_keys
    end

    def result(local_tracks: nil, match_type: nil)
      local_tracks ||= matching_tracks
      match_type ||= if exact_spotify_match?(local_tracks)
        :exact
      elsif local_tracks.any? { |track| curated_track?(track) }
        :likely_duplicate
      else
        :not_found
      end

      {
        source: @track,
        match_type: match_type,
        local_tracks: local_tracks,
        memberships: memberships_for(local_tracks),
        same_title_matches: same_title_matches
      }
    end

    def footprint(scope)
      case scope.to_s
      when "artist" then artist_stats
      when "album" then album_stats
      else
        raise ArgumentError, "Unknown footprint scope"
      end
    end

    private

    def matching_tracks
      exact_match = Track.find_by(spotify_id: @track[:spotify_id])
      return [ exact_match ] if exact_match

      candidate_title = title_key(@track[:name])
      candidate_artist = artist_key(@track[:artist])
      return [] if candidate_title.blank? || candidate_artist.blank?

      title_fragment = title_key(@track[:name]).split.first
      return [] if title_fragment.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(title_fragment)}%"
      Track.where("LOWER(name) LIKE ?", pattern).limit(250).select do |track|
        title_matches?(track.name, candidate_title) &&
          artist_matches?(track.artist, candidate_artist) &&
          compatible_duration?(track.duration_ms)
      end.first(20)
    end

    def exact_spotify_match?(tracks)
      @track[:spotify_id].present? &&
        tracks.any? do |track|
          track.spotify_id == @track[:spotify_id] && curated_track?(track)
        end
    end

    # Listening research is cached as a Track even before it has a crate
    # placement. Such records must never be labelled as being in the crates.
    def curated_track?(track)
      track.playlist_tracks.exists?
    end

    def memberships_for(local_tracks)
      ids = local_tracks.map(&:id)
      return [] if ids.empty?

      PlaylistTrack.includes(:track, playlist: :categories)
                   .where(track_id: ids)
                   .order(:playlist_id, :position)
                   .map do |playlist_track|
        playlist = playlist_track.playlist
        {
          track: playlist_track.track,
          playlist: playlist,
          position: playlist_track.position,
          added_at: playlist_track.added_at,
          categories: playlist.categories.to_a
        }
      end
    end

    def same_title_matches
      key = title_key(@track[:name])
      return [] if key.blank?

      tracks = tracks_with_title_key(key)
      return [] if tracks.empty?

      memberships_by_track = PlaylistTrack.includes(playlist: :categories)
                                          .where(track_id: tracks.map(&:id))
                                          .order(:track_id, :playlist_id, :position)
                                          .group_by(&:track_id)

      tracks.filter_map do |track|
        playlist_tracks = memberships_by_track[track.id]
        next if playlist_tracks.blank?

        memberships = playlist_tracks.map do |playlist_track|
          playlist = playlist_track.playlist
          {
            playlist: playlist,
            position: playlist_track.position,
            categories: ordered_categories(playlist.categories.to_a)
          }
        end

        match_kind = same_title_match_kind(track)

        {
          track: track,
          match_kind: match_kind,
          exact_spotify_id: match_kind == :exact_spotify_id,
          duplicate_playlists: duplicate_playlists_for(memberships),
          memberships: memberships
        }
      end.sort_by do |match|
        [
          same_title_match_priority(match[:match_kind]),
          match[:track].artist.to_s.downcase,
          match[:track].album.to_s.downcase,
          match[:track].name.to_s.downcase
        ]
      end
    end

    def same_title_match_kind(track)
      return :exact_spotify_id if @track[:spotify_id].present? && track.spotify_id == @track[:spotify_id]
      return :strong_artist_variant if strong_artist_variant?(track.artist)

      :different_artist
    end

    def same_title_match_priority(match_kind)
      case match_kind
      when :exact_spotify_id then 0
      when :strong_artist_variant then 1
      else 2
      end
    end

    def duplicate_playlists_for(memberships)
      memberships.group_by { |membership| membership[:playlist].id }
                 .values
                 .filter_map do |playlist_memberships|
        next unless playlist_memberships.size > 1

        {
          playlist: playlist_memberships.first[:playlist],
          positions: playlist_memberships.map { |membership| membership[:position].to_i + 1 }.sort
        }
      end
    end

    # Compare the core song title and primary artist separately from optional
    # release notes and guest credits. The complete names remain visible in the
    # interface; these keys only decide whether two local records are candidates.
    def title_matches?(candidate_title, source_key = title_key(@track[:name]))
      source_key.present? && source_key == title_key(candidate_title)
    end

    def artist_matches?(candidate_artist, source_key = artist_key(@track[:artist]))
      candidate_key = artist_key(candidate_artist)
      return false if source_key.blank? || candidate_key.blank?

      source_key == candidate_key || strong_artist_variant?(candidate_artist)
    end

    def strong_artist_variant?(candidate_artist)
      source_key = artist_identity_key(@track[:artist])
      candidate_key = artist_identity_key(candidate_artist)
      return false if source_key.blank? || candidate_key.blank?
      return true if source_key == candidate_key

      source_family = artist_family_key(source_key)
      candidate_family = artist_family_key(candidate_key)
      return true if source_family.present? && source_family == candidate_family

      source_tokens = source_key.split
      candidate_tokens = candidate_key.split
      shared_tokens = source_tokens & candidate_tokens

      shared_tokens.size >= 2 ||
        (source_tokens - candidate_tokens).empty? ||
        (candidate_tokens - source_tokens).empty?
    end

    def artist_identity_key(value)
      value.to_s.downcase
           .gsub(/\([^\)]*\)|\[[^\]]*\]/, " ")
           .gsub(/\b(?:feat(?:uring)?|with)\b.*/, " ")
           .gsub(/\bft\.?(?=\s|$).*/, " ")
           .gsub(/\bw\/(?=\s).*/, " ")
           .gsub(/\b(the|and)\b/, " ")
           .gsub(/[^a-z0-9]+/, " ")
           .squish
    end

    def artist_family_key(key)
      {
        "bob marley" => "bob-marley-and-the-wailers",
        "bob marley wailers" => "bob-marley-and-the-wailers",
        "wailers" => "bob-marley-and-the-wailers"
      }[key]
    end

    def tracks_with_title_key(key)
      key.split.reduce(Track.all) do |scope, token|
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(token)}%"
        scope.where("LOWER(name) LIKE ?", pattern)
      end.order(:artist, :album, :name).select { |track| title_key(track.name) == key }
    end

    def artist_stats
      key = artist_key(@track[:artist])
      return empty_stats unless key.present?

      tracks = Track.where("LOWER(artist) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(key)}%")
      relationship_stats(tracks)
    end

    def album_stats
      album = @track[:album].to_s.strip
      return empty_stats if album.blank?

      tracks = Track.where("LOWER(album) = ?", album.downcase)
      relationship_stats(tracks)
    end

    def relationship_stats(tracks)
      track_ids = tracks.pluck(:id)
      playlist_tracks = PlaylistTrack.where(track_id: track_ids).includes(playlist: :categories)

      playlists = playlist_tracks.group_by(&:playlist_id).map do |_playlist_id, playlist_memberships|
        playlist = playlist_memberships.first.playlist
        {
          playlist: playlist,
          matching_track_count: playlist_memberships.map(&:track_id).uniq.size,
          categories: ordered_categories(playlist.categories.to_a)
        }
      end.sort_by do |entry|
        playlist = entry[:playlist]
        [ playlist.position || Float::INFINITY, playlist.title.to_s.downcase ]
      end

      categories = ordered_categories(playlists.flat_map { |entry| entry[:categories] }.uniq(&:id))

      {
        track_count: track_ids.size,
        playlist_count: playlists.size,
        category_count: categories.size,
        categories: categories,
        playlists: playlists
      }
    end

    def empty_stats
      { track_count: 0, playlist_count: 0, category_count: 0, categories: [], playlists: [] }
    end

    def ordered_categories(categories)
      categories.sort_by do |category|
        [ category.display_order || category.position || Float::INFINITY, category.name.to_s.downcase ]
      end
    end

    def compatible_duration?(duration_ms)
      reference_duration = @track[:duration_ms].to_i
      return true if reference_duration.zero? || duration_ms.blank?

      (duration_ms.to_i - reference_duration).abs <= DURATION_TOLERANCE_MS
    end

    # A title with a parenthetical mix, version, or guest-credit annotation
    # intentionally compares as its core title. This catches e.g. "Fry
    # Plantain (Radio Edit)" and "Fry Plantain" in the same-title view.
    def title_key(value)
      value.to_s.downcase
           .gsub(/\[[^\]]*\]|\([^\)]*\)/, " ")
           .gsub(/\b(remaster(?:ed)?|mono|stereo|explicit|clean|version)\b/, " ")
           .gsub(/\b(?:feat(?:uring)?|ft\.?)\b.*/, " ")
           .gsub(/[^a-z0-9]+/, " ")
           .squish
    end

    # Featured credits are optional for matching. In particular, both
    # "Fry Plantain (with Joey Bada$)" and "Fry Plantain" become
    # "fry plantain"; the unmodified artist strings still appear to the curator.
    def artist_key(value)
      value.to_s.downcase
           .gsub(/\([^\)]*\)|\[[^\]]*\]/, " ")
           .split(/,|&|\b(?:feat(?:uring)?|with)\b|\bft\.?(?=\s|$)|\bw\/(?=\s)/i)
           .first
           .to_s
           .gsub(/[^a-z0-9]+/, " ")
           .squish
    end
  end
end
