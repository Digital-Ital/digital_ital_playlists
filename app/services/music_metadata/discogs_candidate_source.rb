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
    USER_AGENT = "DigitalItalCrates/1.0 (https://italcrates.com)"

    def initialize(track, deadline: nil)
      @track = track
      @deadline = deadline
    end

    def call
      return skipped unless configured?

      candidate = search_results.find { |result| usable_candidate?(result) }
      return SourceResult.new(source: "discogs_candidate", claims: [], metadata: {}, error: nil) unless candidate

      SourceResult.new(
        source: "discogs_candidate",
        claims: claims_from(candidate),
        metadata: { release_id: candidate["id"] },
        error: nil
      )
    rescue StandardError => e
      SourceResult.new(source: "discogs_candidate", claims: [], metadata: {}, error: "Discogs: #{e.message}")
    end

    private

    def configured?
      ENV["DISCOGS_USER_TOKEN"].present?
    end

    def search_results
      uri = SEARCH_URL.dup
      uri.query = URI.encode_www_form(
        track: @track.name.to_s,
        artist: @track.artist.to_s,
        type: "release",
        per_page: 10
      )
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

      Array(JSON.parse(response.body).fetch("results", []))
    rescue JSON::ParserError
      raise "unreadable response"
    rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => e
      raise "network error (#{e.message})"
    end

    def usable_candidate?(result)
      return false unless result["id"].present? && result["year"].to_s.match?(/\A(?:1[0-9]{3}|20[0-9]{2})\z/)

      title = normalize(result["title"])
      artist_tokens = normalize(@track.artist).split.first(4)
      artist_tokens.any? && artist_tokens.all? { |token| title.include?(token) }
    end

    def claims_from(candidate)
      release_id = candidate.fetch("id").to_s
      source_url = "https://www.discogs.com/release/#{release_id}"

      [
        {
          source_identifier: release_id,
          source_url: source_url,
          field: "release_date",
          value: {
            "text" => candidate.fetch("year").to_s,
            "comparison" => candidate.fetch("year").to_s,
            "context" => "Discogs automatic title / artist search candidate — release or pressing not verified",
            "scope" => "discogs_search_candidate"
          },
          match_confidence: "candidate_title_artist_duration",
          expires_at: 6.hours.from_now
        },
        {
          source_identifier: release_id,
          source_url: source_url,
          field: "release_title",
          value: {
            "text" => candidate["title"].to_s,
            "comparison" => candidate["title"].to_s,
            "context" => "Discogs automatic search candidate release title",
            "scope" => "discogs_search_candidate"
          },
          match_confidence: "candidate_title_artist_duration",
          expires_at: 6.hours.from_now
        }
      ].select { |claim| claim.dig(:value, "text").present? }
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

    def skipped
      SourceResult.new(source: "discogs_candidate", claims: [], metadata: {}, skipped: true, error: nil)
    end
  end
end
