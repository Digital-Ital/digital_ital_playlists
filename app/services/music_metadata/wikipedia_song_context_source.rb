require "json"
require "net/http"
require "timeout"
require "uri"

module MusicMetadata
  # Uses a tightly matched Wikipedia song page as optional context. This is an
  # attributed source extract, not an AI-generated interpretation: ambiguous
  # pages are deliberately ignored.
  class WikipediaSongContextSource
    API_URL = URI("https://en.wikipedia.org/w/api.php")
    USER_AGENT = "DigitalItalCrates/1.0 (https://italcrates.com)"
    MAX_EXTRACT_LENGTH = 420

    def initialize(track, deadline: nil)
      @track = track
      @deadline = deadline
    end

    def call
      return skipped unless lookup_possible?

      page = matching_page
      return no_context unless page

      extract = page["extract"].to_s.squish
      return no_context unless extract.present?

      SourceResult.new(
        source: "wikipedia",
        claims: [ claim(page, excerpt(extract)) ],
        metadata: { page_id: page["pageid"], title: page["title"] },
        error: nil
      )
    rescue StandardError => e
      SourceResult.new(source: "wikipedia", claims: [], metadata: {}, error: "Wikipedia: #{e.message}")
    end

    private

    def lookup_possible?
      @track.name.present? && @track.artist.present? && seconds_remaining.to_f > 1.8
    end

    def matching_page
      pages = get("query").dig("query", "pages").to_h.values
      pages.find { |page| song_page_for_track?(page) }
    end

    # One MediaWiki request supplies both a relevant search result and its
    # plaintext lead extract. Only a title/artist candidate whose lead calls it
    # a song or single is used, avoiding albums and same-title records.
    def get(action)
      uri = API_URL.dup
      uri.query = URI.encode_www_form(
        action: action,
        format: "json",
        generator: "search",
        gsrsearch: [ @track.name, @track.artist ].join(" "),
        gsrlimit: 5,
        prop: "extracts|info",
        inprop: "url",
        exintro: true,
        explaintext: true,
        redirects: 1
      )
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
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

    def song_page_for_track?(page)
      title = normalize(page["title"])
      track_title = normalize(@track.name)
      artist_tokens = normalize(@track.artist).split.first(2)
      extract = page["extract"].to_s.downcase

      title.include?(track_title) &&
        artist_tokens.all? { |token| title.include?(token) || extract.include?(token) } &&
        extract.match?(/\bis (?:an? |the )?(?:\d{4}\s+)?(?:song|single)\b/)
    end

    def excerpt(text)
      return text if text.length <= MAX_EXTRACT_LENGTH

      "#{text[0, MAX_EXTRACT_LENGTH].sub(/\s+\S*\z/, "").rstrip}…"
    end

    def claim(page, text)
      {
        source_identifier: page["pageid"].to_s,
        source_url: page["fullurl"],
        field: "song_context",
        value: {
          "text" => text,
          "comparison" => page["pageid"].to_s,
          "context" => "Wikipedia lead summary for a title / artist song-page candidate",
          "scope" => "wikipedia_song_page"
        },
        match_confidence: "wikipedia_song_candidate"
      }
    end

    def request_timeouts
      remaining = seconds_remaining
      return { open_timeout: 1.2, read_timeout: 2.5 } unless remaining

      raise "refresh time budget exhausted" if remaining <= 0.2

      open_timeout = [ 1.2, remaining / 2 ].min
      read_timeout = [ 2.5, remaining - open_timeout ].min
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

    def no_context
      SourceResult.new(source: "wikipedia", claims: [], metadata: {}, error: nil)
    end

    def skipped
      SourceResult.new(source: "wikipedia", claims: [], metadata: {}, skipped: true, error: nil)
    end
  end
end
