require "json"
require "net/http"
require "timeout"
require "uri"

module MusicMetadata
  # Discogs indexes releases/pressings, not one canonical song. This source
  # therefore records an automatic search result as a candidate only. It never
  # treats a candidate pressing as a verified original release.
  class DiscogsCandidateSource
    SEARCH_URL = URI("https://api.discogs.com/database/search")
    MASTER_BASE_URL = "https://api.discogs.com/masters/"
    RELEASE_BASE_URL = "https://api.discogs.com/releases/"
    USER_AGENT = "DigitalItalCrates/1.0 (https://italcrates.com)"
    CANDIDATE_STRATEGY = "single-then-album-then-verified-track-v7"

    def initialize(track, deadline: nil)
      @track = track
      @deadline = deadline
    end

    def call
      return skipped unless configured?

      # Discogs is release-oriented: first look for a single carrying this
      # track, since that often predates the album. Only if that returns
      # nothing usable do we use the known Spotify album as the discovery key.
      release_candidate = single_release_candidate || album_release_candidate
      candidate = linked_master_for(release_candidate) ||
        release_candidate ||
        album_master_candidate ||
        track_master_candidate

      # Last resort: Discogs search data is release-focused and can miss songs
      # that are album tracks or whose single was not labelled "Single". Query
      # releases by track, then fetch the release and accept it only when its
      # actual tracklist has an exact title (and, where supplied, duration)
      # match. This is deliberately a candidate, never a confirmed recording.
      unless candidate
        relaxed_release_candidate = verified_track_release_candidate
        candidate = linked_master_for(relaxed_release_candidate) || relaxed_release_candidate
      end
      return no_candidate unless candidate

      SourceResult.new(
        source: "discogs_candidate",
        claims: claims_from(
          candidate.fetch(:result),
          candidate.fetch(:kind),
          linked_release_id: candidate[:linked_release_id],
          match_path: candidate[:match_path]
        ),
        metadata: { identifier: candidate.dig(:result, "id"), kind: candidate.fetch(:kind) },
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
      earliest_candidate(
        "release",
        { track: @track.name.to_s, format: "Single" },
        match_path: "single_track"
      )
    end

    def album_release_candidate
      return if @track.album.blank?

      earliest_candidate(
        "release",
        { release_title: @track.album.to_s },
        match_path: "spotify_album"
      )
    end

    def album_master_candidate
      return if @track.album.blank?

      earliest_candidate(
        "master",
        { release_title: @track.album.to_s },
        match_path: "spotify_album"
      )
    end

    def track_master_candidate
      earliest_candidate(
        "master",
        { track: @track.name.to_s },
        match_path: "track_title"
      )
    end

    def earliest_candidate(kind, search_params, match_path:)
      result = ranked_candidates(kind, search_params).first
      result && { result: result, kind: kind, match_path: match_path }
    end

    def ranked_candidates(kind, search_params)
      search_results(kind, search_params)
        .select { |entry| usable_candidate?(entry) }
        .sort_by { |entry| entry.fetch("year").to_i }
    end

    def verified_track_release_candidate
      # Limit the fallback to two earliest eligible releases so an unusual
      # Discogs result cannot turn a live Listening Desk refresh into a crawl.
      ranked_candidates("release", { track: @track.name.to_s }).first(2).each do |candidate|
        release = get_json(URI("#{RELEASE_BASE_URL}#{candidate.fetch("id")}"))
        next unless usable_candidate?(release)
        next unless exact_tracklist_match?(release)

        return {
          result: release,
          kind: "release",
          match_path: "verified_release_track"
        }
      end

      nil
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
      Array(release["tracklist"]).any? do |entry|
        next false unless normalize(entry["title"]) == normalize(@track.name)

        listed_duration = duration_ms(entry["duration"])
        listed_duration.blank? || @track.duration_ms.blank? ||
          (listed_duration - @track.duration_ms.to_i).abs <= 12_000
      end
    end

    def duration_ms(value)
      match = value.to_s.strip.match(/\A(\d+):(\d{2})\z/)
      return unless match

      (match[1].to_i * 60 + match[2].to_i) * 1000
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end

    # A Discogs master is a release family, so searching masters by an
    # individual track title often misses the real family. After finding a
    # compatible single or Spotify-album release, follow its master_id when
    # present to obtain the release-family year and taxonomy.
    def linked_master_for(release_candidate)
      master_id = release_candidate&.dig(:result, "master_id").to_s
      return if master_id.blank? || !master_id.match?(/\A\d+\z/)

      master = get_json(URI("#{MASTER_BASE_URL}#{master_id}"))
      return unless usable_candidate?(master)

      {
        result: master,
        kind: "master",
        linked_release_id: release_candidate.dig(:result, "id"),
        match_path: release_candidate[:match_path]
      }
    rescue StandardError => e
      Rails.logger.info("Discogs master lookup skipped for #{@track.spotify_id}: #{e.message}")
      nil
    end

    def get_json(uri)
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

    def claims_from(candidate, kind, linked_release_id: nil, match_path: nil)
      identifier = candidate.fetch("id").to_s
      source_url = "https://www.discogs.com/#{kind}/#{identifier}"
      context = candidate_context(kind, linked_release_id, match_path)
      match_confidence = match_confidence_for(match_path)

      [
        claim("release_date", candidate.fetch("year").to_s, context, identifier, source_url, kind, match_confidence),
        claim("release_title", candidate["title"].to_s, "#{context} title", identifier, source_url, kind, match_confidence),
        *taxonomy_claims(candidate["genre"] || candidate["genres"], "genre", context, identifier, source_url, kind, match_confidence),
        *taxonomy_claims(candidate["style"] || candidate["styles"], "tag", context, identifier, source_url, kind, match_confidence)
      ].compact
    end

    # The search response already carries Discogs' broad genre and style
    # taxonomy. Keeping it with the automatic candidate gives the Listening
    # Desk useful curation signals without an extra API request, while the
    # context makes clear that it is not a curator-verified pressing.
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
          "scope" => "discogs_#{kind}_candidate",
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
      when "verified_release_track"
        "tracklist-verified track-title / artist"
      else
        "track-title / artist"
      end

      if kind == "master" && linked_release_id.present?
        "Discogs master linked from a #{discovery} candidate — release family, not a verified recording"
      elsif kind == "master"
        "Earliest compatible Discogs master from a #{discovery} candidate — a release family, not a verified recording"
      elsif match_path == "verified_release_track"
        "Discogs release whose tracklist contains the exact song title — release-level data, not a confirmed recording"
      else
        "Earliest compatible Discogs #{discovery} release candidate — pressing not verified"
      end
    end

    def match_confidence_for(match_path)
      return "candidate_verified_track_release" if match_path == "verified_release_track"

      "candidate_title_artist_duration"
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
      # An automatic Discogs search has no guaranteed match for every song.
      # Treat a clean absence as no data, not an application failure.
      SourceResult.new(source: "discogs_candidate", claims: [], metadata: {}, error: nil)
    end

    def skipped
      SourceResult.new(source: "discogs_candidate", claims: [], metadata: {}, skipped: true, error: nil)
    end
  end
end
