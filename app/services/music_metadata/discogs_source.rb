require "json"
require "net/http"
require "timeout"
require "uri"

module MusicMetadata
  class DiscogsSource
    API_BASE_URL = "https://api.discogs.com/releases/"
    USER_AGENT = "DigitalItalCrates/1.0 (https://italcrates.com)"

    def initialize(track, enrichment, deadline: nil)
      @track = track
      @enrichment = enrichment
      @deadline = deadline
    end

    def call
      return skipped(reason: "not_configured") unless configured?
      return skipped(reason: "no_selected_release") if release_id.blank?

      payload = release_payload
      matching_tracks = matching_release_tracks(payload)
      return mismatch unless matching_tracks.any?

      SourceResult.new(
        source: "discogs",
        claims: claims_from(payload, matching_tracks),
        metadata: { release_id: release_id },
        error: nil,
        outcome: "claims",
        outcome_reason: "curator_selected_release"
      )
    rescue StandardError => e
      error_result(e)
    end

    private

    def configured?
      ENV["DISCOGS_USER_TOKEN"].present?
    end

    def release_id
      @enrichment.discogs_release_id
    end

    def release_payload
      uri = URI("#{API_BASE_URL}#{release_id}")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Discogs token=#{ENV.fetch("DISCOGS_USER_TOKEN")}"
      request["User-Agent"] = USER_AGENT

      timeouts = request_timeouts
      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: true,
        open_timeout: timeouts.fetch(:open_timeout),
        read_timeout: timeouts.fetch(:read_timeout)
      ) do |http|
        http.request(request)
      end
      raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError
      raise "unreadable response"
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => e
      raise "network error (#{e.message})"
    end

    def matching_release_tracks(payload)
      title = normalize(@track.name)

      Array(payload["tracklist"]).select do |entry|
        next false unless normalize(entry["title"]) == title

        artist = track_artist(entry)
        artist.blank? || compatible_artist?(artist)
      end
    end

    def track_artist(entry)
      artists = entry["artists"] || entry["artist"]
      Array(artists).filter_map do |artist|
        artist.is_a?(Hash) ? artist["name"] : artist
      end.join(", ").presence
    end

    def compatible_artist?(candidate)
      source_tokens = normalize(@track.artist).split
      candidate_tokens = normalize(candidate).split
      return false if source_tokens.empty? || candidate_tokens.empty?

      (source_tokens - candidate_tokens).empty? || (candidate_tokens - source_tokens).empty?
    end

    def claims_from(payload, matching_tracks)
      source_url = "https://www.discogs.com/release/#{release_id}"
      source_identifier = release_id
      release_date = payload["released"].presence || payload["year"].presence
      track_level_claims = if matching_tracks.one?
        credit_claims(
          matching_tracks.first["extraartists"],
          "Discogs track-level credit from a single compatible title match",
          source_identifier,
          source_url,
          scope: "discogs_selected_release_track"
        )
      else
        []
      end
      track_position_claim = if matching_tracks.one?
        claim(
          "release_position",
          matching_tracks.first["position"],
          "Discogs track position on the curator-selected release",
          source_identifier,
          source_url,
          scope: "discogs_selected_release_track"
        )
      end

      [
        claim(
          "release_date",
          release_date,
          "Discogs curator-selected release date",
          source_identifier,
          source_url
        ),
        claim(
          "release_country",
          payload["country"],
          "Discogs release-market country (not an origin claim)",
          source_identifier,
          source_url
        ),
        claim("release_title", payload["title"], "Discogs curator-selected release", source_identifier, source_url),
        *format_claims(payload["formats"], source_identifier, source_url),
        track_position_claim,
        *label_claims(payload["labels"], source_identifier, source_url),
        *credit_claims(
          payload["extraartists"],
          "Discogs release-level credit (may apply to the full release)",
          source_identifier,
          source_url
        ),
        *track_level_claims,
        *tag_claims(payload, source_identifier, source_url)
      ].compact
    end

    def format_claims(formats, source_identifier, source_url)
      Array(formats).filter_map do |format|
        parts = [
          format["name"],
          *Array(format["descriptions"]),
          format["text"]
        ].filter_map { |part| part.to_s.strip.presence }.uniq
        next if parts.empty?

        claim(
          "release_format",
          parts.join(" · "),
          "Discogs curator-selected release format",
          source_identifier,
          source_url
        )
      end.uniq { |entry| entry.dig(:value, "text") }
    end

    def label_claims(labels, source_identifier, source_url)
      Array(labels).flat_map do |label|
        [
          claim("label", label["name"], "Discogs release label", source_identifier, source_url),
          claim(
            "catalogue_number",
            label["catno"],
            "Discogs release catalogue number",
            source_identifier,
            source_url
          )
        ]
      end
    end

    def credit_claims(credits, context, source_identifier, source_url, scope: "discogs_selected_release")
      Array(credits).flat_map do |credit|
        name = credit["name"].to_s.strip
        next [] if name.blank?

        credit_fields(credit["role"]).filter_map do |field|
          claim(field, name, context, source_identifier, source_url, scope: scope)
        end
      end.uniq { |entry| [ entry[:field], entry.dig(:value, "text") ] }
    end

    def credit_fields(role)
      role.to_s.downcase.split(%r{[;,/]}).filter_map do |part|
        case part
        when /producer/
          "producer"
        when /master/
          "mastering_engineer"
        when /engineer/
          "engineer"
        when /mixer/
          "mixer"
        when /lyric/
          "lyricist"
        when /written|writer/
          "writer"
        when /composer|composed/
          "composer"
        when /arrang/
          "arranger"
        when /perform|vocals|guitar|drums|bass|keyboard|percussion/
          "performer"
        end
      end.uniq
    end

    def tag_claims(payload, source_identifier, source_url)
      Array(payload["genres"]).filter_map do |genre|
        claim("genre", genre, "Discogs release genre", source_identifier, source_url)
      end +
        Array(payload["styles"]).filter_map do |style|
          claim("tag", style, "Discogs release style", source_identifier, source_url)
        end
    end

    def claim(field, text, context, source_identifier, source_url, scope: "discogs_selected_release")
      return if text.blank?

      {
        source_identifier: source_identifier,
        source_url: source_url,
        field: field,
        value: {
          "text" => text.to_s,
          "comparison" => text.to_s,
          "context" => context,
          "scope" => scope
        },
        match_confidence: "curator_selected_release",
        expires_at: 6.hours.from_now
      }
    end

    def mismatch
      SourceResult.new(
        source: "discogs",
        claims: [],
        metadata: {},
        error: "Discogs: the selected release does not contain a compatible title and track artist.",
        outcome: "error",
        outcome_reason: "selected_release_mismatch"
      )
    end

    def skipped(reason:, error: nil)
      SourceResult.new(
        source: "discogs",
        claims: [],
        metadata: {},
        skipped: true,
        error: error,
        outcome: "skipped",
        outcome_reason: reason
      )
    end

    def error_result(error)
      if error.message == "refresh time budget exhausted"
        return skipped(
          reason: "time_budget",
          error: "Discogs: protected lookup time was exhausted before a request could start."
        )
      end

      SourceResult.new(
        source: "discogs",
        claims: [],
        metadata: {},
        error: "Discogs: #{error.message}",
        outcome: "error",
        outcome_reason: error_reason(error)
      )
    end

    def error_reason(error)
      case error.message
      when /rate limited/i then "rate_limited"
      when /network error|Net::(?:Open|Read)Timeout/i then "network"
      else "provider_error"
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

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end
  end
end
