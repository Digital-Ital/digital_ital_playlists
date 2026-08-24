require "json"
require "net/http"
require "thread"
require "timeout"
require "uri"

module MusicMetadata
  # Discogs indexes releases/pressings, not one canonical song. Automatic
  # results remain candidate evidence and are validated against a release
  # tracklist before their metadata can appear in the Listening Desk.
  class DiscogsCandidateSource
    SEARCH_URL = URI("https://api.discogs.com/database/search")
    MASTER_BASE_URL = "https://api.discogs.com/masters/"
    RELEASE_BASE_URL = "https://api.discogs.com/releases/"
    USER_AGENT = "DigitalItalCrates/1.0 (https://italcrates.com)"
    REQUEST_INTERVAL_SECONDS = 1.1
    REQUEST_MUTEX = Mutex.new
    CANDIDATE_STRATEGY = "validated-single-album-relaxed-track-v8"
    MAX_RELEASE_VALIDATIONS = 3

    class << self
      attr_accessor :last_request_at
    end

    def initialize(track, spotify_album: nil, deadline: nil)
      @track = track
      @spotify_album = spotify_album.is_a?(Hash) ? spotify_album : {}
      @deadline = deadline
      @release_validations = 0
    end

    def call
      return skipped unless configured?

      # Discogs is release-oriented. Check a track-bearing single first, then
      # the Spotify album. Each raw search result is fetched and checked against
      # its actual tracklist before it may be used.
      release_candidate = single_release_candidate ||
        spotify_album_release_candidate ||
        relaxed_track_release_candidate
      return no_candidate unless release_candidate

      master_candidate = linked_master_for(release_candidate)
      claims = claims_from(
        release_candidate.fetch(:result),
        "release",
        match_path: release_candidate.fetch(:match_path)
      )
      if master_candidate.present?
        claims.concat(
          claims_from(
            master_candidate.fetch(:result),
            "master",
            linked_release_id: release_candidate.dig(:result, "id"),
            match_path: release_candidate.fetch(:match_path)
          )
        )
      end

      SourceResult.new(
        source: "discogs_candidate",
        claims: claims,
        metadata: {
          outcome: "found",
          mode: "automatic_candidate",
          identifier: release_candidate.dig(:result, "id"),
          kind: "release",
          master_identifier: master_candidate&.dig(:result, "id")
        },
        error: nil
      )
    rescue StandardError => e
      SourceResult.new(source: "discogs_candidate", claims: [], metadata: {}, error: "Discogs: #{e.message}")
    end

    private

    def configured?
      ENV["DISCOGS_USER_TOKEN"].present?
    end

    def single_release_candidate
      validated_release_candidate(
        { track: @track.name.to_s, format: "Single" },
        match_path: "single_track"
      )
    end

    def spotify_album_release_candidate
      return if spotify_album_name.blank?

      validated_release_candidate(
        { release_title: spotify_album_name },
        match_path: "spotify_album",
        require_spotify_album_title: true
      )
    end

    # This is intentionally last. It catches an album, EP, or compilation
    # whose song was not marked as a Discogs "Single", but accepts it only
    # after an exact tracklist title/duration check.
    def relaxed_track_release_candidate
      validated_release_candidate(
        { track: @track.name.to_s },
        match_path: "verified_release_track"
      )
    end

    def validated_release_candidate(search_params, match_path:, require_spotify_album_title: false)
      # One earliest result per discovery path keeps the fallback bounded and
      # preserves the deliberate order: single, then Spotify album, then
      # general track-bearing release.
      candidate = ranked_candidates("release", search_params).first
      return unless candidate

      release = release_detail(candidate)
      return unless usable_candidate?(release)
      return unless exact_tracklist_match?(release)
      return unless compatible_artist_on_release?(release)
      return if require_spotify_album_title && !spotify_album_title_matches?(release)

      { result: release, kind: "release", match_path: match_path }
    end

    def release_detail(candidate)
      return if @release_validations >= MAX_RELEASE_VALIDATIONS

      @release_validations += 1
      get_json(URI("#{RELEASE_BASE_URL}#{candidate.fetch("id")}"))
    end

    def ranked_candidates(kind, search_params)
      search_results(kind, search_params)
        .select { |entry| usable_candidate?(entry) }
        .sort_by { |entry| entry.fetch("year").to_i }
    end

    def search_results(kind, search_params)
      uri = SEARCH_URL.dup
      uri.query = URI.encode_www_form(
        {
          artist: @track.artist.to_s,
          type: kind,
          sort: "year",
          sort_order: "asc",
          per_page: 50
        }.merge(search_params)
      )

      Array(get_json(uri).fetch("results", []))
    end

    def exact_tracklist_match?(release)
      matching_track_entries(release).any?
    end

    def matching_track_entries(release)
      return [] if @track.duration_ms.blank?

      Array(release["tracklist"]).select do |entry|
        next false unless entry["type_"].to_s == "track"
        next false unless normalize(entry["title"]) == normalize(@track.name)

        listed_duration = duration_ms(entry["duration"])
        listed_duration.present? &&
          (listed_duration - @track.duration_ms.to_i).abs <= 12_000
      end
    end

    # The search request already includes Spotify's artist string. This local
    # check prevents a fuzzy Discogs search result with another artist from
    # borrowing facts for a same-titled song. Track-level artists take priority
    # when Discogs supplies them; otherwise the release-level artist is used.
    def compatible_artist_on_release?(release)
      entries = matching_track_entries(release)
      names = entries.flat_map { |entry| artist_names(entry["artists"]) }
      names = artist_names(release["artists"]) if names.empty?
      names = names.reject { |name| generic_artist_name?(name) }

      # The search request has an artist filter, but it can be fuzzy. Require
      # a compatible artist in the detailed release payload before asserting an
      # exact tracklist candidate.
      names.any? { |name| compatible_artist?(name) }
    end

    def artist_names(artists)
      Array(artists).filter_map { |artist| artist.is_a?(Hash) ? artist["name"] : artist.to_s.presence }
    end

    def generic_artist_name?(name)
      normalize(name).in?([ "various", "various artists", "va" ])
    end

    def compatible_artist?(candidate)
      source = normalize(@track.artist)
      candidate_name = normalize(candidate)
      return true if source.present? && source == candidate_name

      source_tokens = artist_identity_tokens(source)
      candidate_tokens = artist_identity_tokens(candidate_name)
      return false if source_tokens.size < 2 || candidate_tokens.size < 2

      (source_tokens - candidate_tokens).empty? || (candidate_tokens - source_tokens).empty?
    end

    def artist_identity_tokens(value)
      value.to_s.split - %w[the and feat featuring with dj]
    end

    def spotify_album_title_matches?(release)
      normalize(release["title"]) == normalize(spotify_album_name)
    end

    def spotify_album_name
      @spotify_album["name"].to_s.presence
    end

    # A Discogs master is a release family. It is shown alongside—not instead
    # of—the validated release, so its earlier family year never masquerades
    # as the precise release that proved the song placement.
    def linked_master_for(release_candidate)
      master_id = release_candidate&.dig(:result, "master_id").to_s
      return if master_id.blank? || !master_id.match?(/\A\d+\z/)

      master = get_json(URI("#{MASTER_BASE_URL}#{master_id}"))
      return unless usable_candidate?(master)

      { result: master, kind: "master" }
    rescue StandardError => e
      Rails.logger.info("Discogs master lookup skipped for #{@track.spotify_id}: #{e.message}")
      nil
    end

    def get_json(uri)
      reserve_request_slot

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Discogs token=#{ENV.fetch("DISCOGS_USER_TOKEN")}"
      request["User-Agent"] = USER_AGENT

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: true,
        open_timeout: request_timeouts.fetch(:open_timeout),
        read_timeout: request_timeouts.fetch(:read_timeout)
      ) { |http| http.request(request) }
      if response.code == "429"
        retry_after = response["Retry-After"].to_i
        suffix = retry_after.positive? ? " (retry after #{retry_after}s)" : ""
        raise "rate limited#{suffix}"
      end
      raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError
      raise "unreadable response"
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => e
      raise "network error (#{e.message})"
    end

    def usable_candidate?(result)
      result["id"].present? && result["year"].to_s.match?(/^(?:1[0-9]{3}|20[0-9]{2})$/)
    end

    def claims_from(candidate, kind, linked_release_id: nil, match_path:)
      identifier = candidate.fetch("id").to_s
      source_url = "https://www.discogs.com/#{kind}/#{identifier}"
      context = candidate_context(kind, linked_release_id, match_path)
      match_confidence = kind == "master" ? "candidate_linked_release_master" : "candidate_verified_track_release"

      [
        claim("release_date", candidate.fetch("year").to_s, context, identifier, source_url, kind, match_confidence),
        claim("release_title", candidate["title"].to_s, "#{context} title", identifier, source_url, kind, match_confidence),
        *taxonomy_claims(candidate["genre"] || candidate["genres"], "genre", context, identifier, source_url, kind, match_confidence),
        *taxonomy_claims(candidate["style"] || candidate["styles"], "tag", context, identifier, source_url, kind, match_confidence)
      ].compact
    end

    def taxonomy_claims(values, field, context, identifier, source_url, kind, match_confidence)
      Array(values).filter_map do |value|
        claim(
          field,
          value,
          "#{context} #{field == "genre" ? "genre" : "style"}",
          identifier,
          source_url,
          kind,
          match_confidence
        )
      end.uniq { |entry| entry.dig(:value, "text").to_s.downcase }
    end

    def claim(field, text, context, identifier, source_url, kind, match_confidence)
      return if text.blank?

      {
        source_identifier: identifier,
        source_url: source_url,
        field: field,
        value: {
          "text" => text,
          "comparison" => text,
          "context" => context,
          "scope" => "discogs_#{kind}_candidate:#{identifier}",
          "candidate_strategy" => CANDIDATE_STRATEGY
        },
        match_confidence: match_confidence,
        expires_at: 6.hours.from_now
      }
    end

    def candidate_context(kind, linked_release_id, match_path)
      discovery = case match_path
      when "single_track"
        "single / track-title"
      when "spotify_album"
        "Spotify album / artist"
      else
        "tracklist-verified track-title / artist"
      end

      if kind == "master" && linked_release_id.present?
        "Discogs master linked from a #{discovery} release — release-family context, not a verified recording"
      elsif kind == "master"
        "Discogs master from a #{discovery} release — release-family context, not a verified recording"
      else
        "Discogs release with an exact tracklist title and compatible artist — release-level data, not a confirmed recording"
      end
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end

    def duration_ms(value)
      match = value.to_s.strip.match(/\A(\d+):(\d{2})\z/)
      return unless match

      (match[1].to_i * 60 + match[2].to_i) * 1000
    end

    def reserve_request_slot
      REQUEST_MUTEX.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        elapsed = now - self.class.last_request_at.to_f
        wait_seconds = [ REQUEST_INTERVAL_SECONDS - elapsed, 0 ].max

        if seconds_remaining && wait_seconds >= seconds_remaining
          raise "refresh time budget exhausted"
        end

        sleep(wait_seconds) if wait_seconds.positive?
        self.class.last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    def request_timeouts
      remaining = seconds_remaining
      return { open_timeout: 1.5, read_timeout: 3 } unless remaining

      raise "refresh time budget exhausted" if remaining <= 0.2

      open_timeout = [ 1.5, remaining / 2 ].min
      read_timeout = [ 3, remaining - open_timeout ].min
      raise "refresh time budget exhausted" if read_timeout <= 0.1

      { open_timeout: open_timeout, read_timeout: read_timeout }
    end

    def seconds_remaining
      return unless @deadline

      @deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def no_candidate
      SourceResult.new(
        source: "discogs_candidate",
        claims: [],
        metadata: {
          outcome: "no_safe_candidate",
          reason: "no_safe_candidate",
          mode: "automatic_candidate"
        },
        error: nil
      )
    end

    def skipped
      SourceResult.new(
        source: "discogs_candidate",
        claims: [],
        metadata: {
          outcome: "skipped",
          reason: "not_configured",
          mode: "automatic_candidate"
        },
        skipped: true,
        error: nil
      )
    end
  end
end
