module Spotify
  class CrateLookup
    DURATION_TOLERANCE_MS = 12_000

    def self.from_spotify(track)
      new(track).result
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
      match_type ||= local_tracks.any? ? :likely_duplicate : :not_found

      {
        source: @track,
        match_type: match_type,
        local_tracks: local_tracks,
        memberships: memberships_for(local_tracks),
        artist_stats: artist_stats,
        album_stats: album_stats
      }
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
        title_key(track.name) == candidate_title &&
          artist_key(track.artist) == candidate_artist &&
          compatible_duration?(track.duration_ms)
      end.first(20)
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

      {
        track_count: tracks.count,
        playlist_count: playlist_tracks.select(:playlist_id).distinct.count,
        category_count: playlist_tracks.joins(playlist: :categories).select("categories.id").distinct.count,
        categories: playlist_tracks.flat_map { |playlist_track| playlist_track.playlist.categories.to_a }.uniq(&:id)
      }
    end

    def empty_stats
      { track_count: 0, playlist_count: 0, category_count: 0, categories: [] }
    end

    def compatible_duration?(duration_ms)
      reference_duration = @track[:duration_ms].to_i
      return true if reference_duration.zero? || duration_ms.blank?

      (duration_ms.to_i - reference_duration).abs <= DURATION_TOLERANCE_MS
    end

    def title_key(value)
      value.to_s.downcase
           .gsub(/\[[^\]]*\]|\([^\)]*\)/, " ")
           .gsub(/\b(remaster(?:ed)?|mono|stereo|explicit|clean|version)\b/, " ")
           .gsub(/\bfeat(?:uring)?\.?\b.*/, " ")
           .gsub(/[^a-z0-9]+/, " ")
           .squish
    end

    def artist_key(value)
      value.to_s.downcase
           .split(/,|&|\bfeat(?:uring)?\.?\b/i)
           .first
           .to_s
           .gsub(/[^a-z0-9]+/, " ")
           .squish
    end
  end
end
