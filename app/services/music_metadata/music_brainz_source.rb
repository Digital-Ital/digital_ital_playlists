require "json"
require "net/http"
require "thread"
require "timeout"
require "uri"

module MusicMetadata
  class MusicBrainzSource
    BASE_URL = "https://musicbrainz.org/ws/2/"
    USER_AGENT = "DigitalItalCrates/1.0 (https://italcrates.com)"
    REQUEST_INTERVAL_SECONDS = 1.1
    REQUEST_MUTEX = Mutex.new
    MAX_REQUESTS_PER_REFRESH = 4
    CREDIT_FIELDS = {
      "producer" => "producer",
      "engineer" => "engineer",
      "mixer" => "mixer",
      "performer" => "performer"
    }.freeze
    WRITING_FIELDS = {
      "writer" => "writer",
      "composer" => "composer",
      "lyricist" => "lyricist",
      "arranger" => "arranger"
    }.freeze
    FACT_TYPES = %w[cover samples material remix remixer].freeze

    class << self
      attr_accessor :last_request_at
    end

    def initialize(track, isrc:, spotify_album: nil, deadline: nil)
      @track = track
      @isrc = isrc.presence
      @spotify_album = spotify_album.is_a?(Hash) ? spotify_album : {}
      @deadline = deadline
      @request_count = 0
    end

    def call
      candidate, match_confidence = find_candidate
      return no_candidate unless candidate

      recording = get(
        "recording/#{candidate.fetch("id")}",
        inc: "artist-credits+isrcs+releases+artist-rels+work-rels+recording-rels+place-rels+tags+genres"
      )
      return no_candidate if album_supported_candidate?(match_confidence) &&
        !recording_has_spotify_album?(recording)

      work = fetch_work(recording)
      source_url = "https://musicbrainz.org/recording/#{recording.fetch("id")}"

      SourceResult.new(
        source: "musicbrainz",
        claims: claims_from(recording, candidate, work, source_url, match_confidence),
        metadata: { recording_id: recording["id"], match_confidence: match_confidence },
        error: nil
      )
    rescue StandardError => e
      SourceResult.new(source: "musicbrainz", claims: [], metadata: {}, error: "MusicBrainz: #{e.message}")
    end

    private

    def find_candidate
      if @isrc.present?
        # An ISRC lookup already returns its recordings. MusicBrainz rejects
        # inc=recordings here with HTTP 400, so do not add a subquery.
        payload = get("isrc/#{URI.encode_www_form_component(@isrc)}", allow_not_found: true)
        candidate = Array(payload.to_h["recordings"]).first
        return [ candidate, "isrc_exact" ] if candidate.present?
      end

      return [ nil, nil ] if @track.name.blank? || @track.artist.blank?

      candidate = recording_candidates(strict_recording_query)
        .find { |recording| strict_recording_match?(recording) }
      return [ candidate, "candidate_title_artist_duration" ] if candidate.present?

      # A track may be indexed under a release's artist credit or title rather
      # than Spotify's display strings. Only after the strict lookup fails, add
      # Spotify's album as a second source-side clue. The local exact-title,
      # compatible-artist, and duration checks remain unchanged, so this route
      # cannot accept a merely similar song.
      candidate = recording_candidates(album_supported_recording_query)
        .find { |recording| album_supported_recording_match?(recording) }
      return [ candidate, "candidate_album_title_artist_duration" ] if candidate.present?

      [ nil, nil ]
    end

    def strict_recording_query
      %(recording:"#{search_value(@track.name)}" AND artist:"#{search_value(@track.artist)}")
    end

    def album_supported_recording_query
      return if spotify_album_name.blank?

      # The source-side album phrase is an extra clue only. The candidate is
      # still rejected unless the title, artist, duration, and detailed
      # recording release list all agree with Spotify's current album payload.
      %(recording:"#{search_value(@track.name)}" AND artist:"#{search_value(@track.artist)}" AND release:"#{search_value(spotify_album_name)}")
    end

    def recording_candidates(query)
      return [] if query.blank?

      payload = get("recording/", query: query, limit: 5)
      Array(payload["recordings"])
    end

    def album_supported_recording_match?(recording)
      return false if @track.duration_ms.blank? || recording["length"].blank?

      strict_recording_match?(recording)
    end

    def album_supported_candidate?(match_confidence)
      match_confidence == "candidate_album_title_artist_duration"
    end

    def recording_has_spotify_album?(recording)
      Array(recording["releases"]).any? do |release|
        normalize(release["title"]) == normalize(spotify_album_name)
      end
    end

    def spotify_album_name
      @spotify_album["name"].to_s.presence
    end

    def fetch_work(recording)
      relation = Array(recording["relations"]).find do |item|
        item["target-type"] == "work" && item.dig("work", "id").present?
      end
      return nil unless relation

      # This source is refreshed as one atomic claim set. If an optional work
      # request times out (or the bounded request budget is exhausted), let the
      # normal source error path preserve every previously saved MusicBrainz
      # fact rather than silently replacing writer/work claims with a partial
      # recording-only result.
      raise "request cap reached before linked work lookup" unless request_budget_available?

      get("work/#{relation.dig("work", "id")}", inc: "artist-rels", allow_not_found: true)
    end

    def claims_from(recording, candidate, work, source_url, match_confidence)
      release = first_known_release(recording, candidate)
      recording_id = recording["id"]

      [
        claim(
          "isrc",
          recording_isrc(recording),
          "MusicBrainz recording ISRC",
          recording_id,
          source_url,
          match_confidence,
          scope: "recording"
        ),
        claim(
          "release_date",
          release[:date],
          "MusicBrainz earliest known release",
          recording_id,
          source_url,
          match_confidence,
          scope: "musicbrainz_first_known_release"
        ),
        claim(
          "release_country",
          release[:country],
          "Country of the MusicBrainz release matching the earliest-known date",
          recording_id,
          source_url,
          match_confidence,
          scope: "musicbrainz_first_known_release"
        ),
        claim(
          "release_title",
          release[:title],
          "MusicBrainz release matching the earliest-known date",
          recording_id,
          source_url,
          match_confidence,
          scope: "musicbrainz_first_known_release"
        ),
        claim(
          "recording_note",
          recording["disambiguation"],
          "MusicBrainz recording disambiguation",
          recording_id,
          source_url,
          match_confidence,
          scope: "musicbrainz_recording"
        ),
        *recording_location_claims(
          recording["relations"],
          recording_id,
          source_url,
          match_confidence
        ),
        *work_claims(work, source_url, match_confidence),
        *relationship_claims(
          recording["relations"],
          CREDIT_FIELDS,
          recording_id,
          source_url,
          match_confidence,
          scope: "musicbrainz_recording"
        ),
        *relationship_claims(
          work&.fetch("relations", []),
          WRITING_FIELDS,
          recording_id,
          source_url,
          match_confidence,
          scope: "musicbrainz_work"
        ),
        *fact_claims(recording["relations"], recording_id, source_url, match_confidence),
        *tag_claims(recording, recording_id, source_url, match_confidence)
      ].compact
    end

    def work_claims(work, fallback_source_url, match_confidence)
      return [] unless work.present?

      work_id = work["id"]
      source_url = work_id.present? ? "https://musicbrainz.org/work/#{work_id}" : fallback_source_url

      [
        claim(
          "work_title",
          work["title"],
          "MusicBrainz linked composition/work",
          work_id,
          source_url,
          match_confidence,
          scope: "musicbrainz_work"
        ),
        claim(
          "work_type",
          work["type"],
          "MusicBrainz linked work type",
          work_id,
          source_url,
          match_confidence,
          scope: "musicbrainz_work"
        ),
        claim(
          "work_disambiguation",
          work["disambiguation"],
          "MusicBrainz work disambiguation",
          work_id,
          source_url,
          match_confidence,
          scope: "musicbrainz_work"
        ),
        *Array(work["iswcs"]).filter_map do |iswc|
          claim(
            "iswc",
            iswc,
            "MusicBrainz linked work ISWC",
            work_id,
            source_url,
            match_confidence,
            scope: "musicbrainz_work"
          )
        end
      ].compact
    end

    def recording_location_claims(relations, source_identifier, source_url, match_confidence)
      location_types = [ "recorded at", "mixed at", "mastered at", "produced at" ]

      Array(relations).filter_map do |relation|
        next unless location_types.include?(relation["type"])

        place = relation["place"] || relation["target"]
        name = place.is_a?(Hash) ? place["name"] : nil
        next if name.blank?

        date_range = [ relation["begin"], relation["end"] ].compact.join("–").presence
        context = "MusicBrainz session/location relationship"
        context = "#{context} (#{date_range})" if date_range.present?

        claim(
          "recording_location",
          "#{relation["type"].to_s.humanize}: #{name}",
          context,
          source_identifier,
          source_url,
          match_confidence,
          scope: "musicbrainz_recording"
        )
      end.uniq { |entry| entry.dig(:value, "text") }
    end

    def first_known_release(recording, candidate)
      releases = Array(recording["releases"]).select { |release| release["date"].present? }
      earliest = releases.min_by { |release| release["date"] }
      date = candidate["first-release-date"].presence || earliest&.dig("date")
      release = releases.find { |item| item["date"] == date }

      {
        date: date,
        country: release&.dig("country"),
        title: release&.dig("title")
      }
    end

    def relationship_claims(relations, field_map, source_identifier, source_url, match_confidence, scope:)
      Array(relations).filter_map do |relation|
        field = field_map[relation["type"]]
        next unless field

        artist = relation["artist"] || relation["target"]
        name = artist.is_a?(Hash) ? artist["name"] : nil
        next if name.blank?

        claim(
          field,
          name,
          "MusicBrainz #{relation["type"]} credit",
          source_identifier,
          source_url,
          match_confidence,
          scope: scope
        )
      end.uniq { |entry| [ entry[:field], entry.dig(:value, "text") ] }
    end

    def fact_claims(relations, source_identifier, source_url, match_confidence)
      Array(relations).filter_map do |relation|
        next unless FACT_TYPES.include?(relation["type"])

        target = relation["recording"] || relation["work"] || relation["artist"] || relation["target"]
        label = target.is_a?(Hash) ? target["title"].presence || target["name"] : nil
        text = [ relation["type"].to_s.humanize, label ].compact.join(": ")
        claim(
          "relationship_fact",
          text,
          "MusicBrainz recording relationship",
          source_identifier,
          source_url,
          match_confidence,
          scope: "musicbrainz_recording"
        )
      end.uniq { |entry| entry.dig(:value, "text") }
    end

    def tag_claims(recording, source_identifier, source_url, match_confidence)
      Array(recording["genres"]).filter_map do |genre|
        claim(
          "genre",
          genre["name"],
          musicbrainz_tag_context("genre", genre),
          source_identifier,
          source_url,
          match_confidence,
          scope: "musicbrainz_recording"
        )
      end +
        Array(recording["tags"]).filter_map do |tag|
          claim(
            "tag",
            tag["name"],
            musicbrainz_tag_context("tag", tag),
            source_identifier,
            source_url,
            match_confidence,
            scope: "musicbrainz_recording"
          )
        end
    end

    def musicbrainz_tag_context(kind, tag)
      support = tag["count"].to_i
      return "MusicBrainz recording #{kind}" unless support.positive?

      "MusicBrainz recording #{kind} (#{support} community votes)"
    end

    def claim(field, text, context, source_identifier, source_url, match_confidence, scope:)
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
        match_confidence: match_confidence
      }
    end

    def strict_recording_match?(recording)
      title_matches = normalize(recording["title"]) == normalize(@track.name)
      credited_artists = Array(recording["artist-credit"]).filter_map do |credit|
        credit.dig("artist", "name") || credit["name"]
      end.join(" ")
      artist_matches = shared_artist_identity?(credited_artists)
      duration_matches = @track.duration_ms.present? && recording["length"].present? &&
        (recording["length"].to_i - @track.duration_ms.to_i).abs <= 12_000

      title_matches && artist_matches && duration_matches
    end

    def shared_artist_identity?(candidate)
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

    def get(path, params = {}, allow_not_found: false, **keyword_params)
      params = params.to_h.merge(keyword_params)
      attempts = 0

      begin
        consume_request_budget!
        reserve_request_slot

        uri = URI("#{BASE_URL}#{path}")
        uri.query = URI.encode_www_form(params.merge(fmt: "json"))
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
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
        return nil if response.code == "404" && allow_not_found
        raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        attempts += 1
        retry if attempts == 1 && retryable_timeout?

        raise "network error (#{e.message})"
      rescue JSON::ParserError
        raise "unreadable response"
      rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => e
        raise "network error (#{e.message})"
      end
    end

    def request_budget_available?
      @request_count < MAX_REQUESTS_PER_REFRESH
    end

    def consume_request_budget!
      raise "request cap reached" unless request_budget_available?

      @request_count += 1
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

    def recording_isrc(recording)
      return if @isrc.blank?

      Array(recording["isrcs"]).find { |isrc| isrc.to_s.casecmp?(@isrc.to_s) }
    end

    def request_timeouts
      remaining = seconds_remaining
      return { open_timeout: 3.5, read_timeout: 4 } unless remaining

      raise "refresh time budget exhausted" if remaining <= 0.2

      open_timeout = [ 3.5, remaining / 2 ].min
      read_timeout = [ 4, remaining - open_timeout ].min
      raise "refresh time budget exhausted" if read_timeout <= 0.1

      { open_timeout: open_timeout, read_timeout: read_timeout }
    end

    def retryable_timeout?
      seconds_remaining.nil? || seconds_remaining > 5
    end

    def seconds_remaining
      return unless @deadline

      @deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def search_value(value)
      # Escape Lucene operators before the quoted phrase is URL-encoded. Track
      # titles such as "A/B (Dub)" must remain literal search text.
      value.to_s.gsub(%r{[+\-!(){}\[\]^"~*?:\\/&|]}) { |character| "\\#{character}" }
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end

    def no_candidate
      # A completed lookup with no safe match is normal absence, not an API
      # failure. Returning an empty successful result clears old candidate
      # claims rather than leaving stale source evidence on a new version.
      SourceResult.new(source: "musicbrainz", claims: [], metadata: {}, error: nil)
    end

    def skipped
      SourceResult.new(source: "musicbrainz", claims: [], metadata: {}, skipped: true, error: nil)
    end
  end
end
