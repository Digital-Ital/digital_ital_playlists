require "json"
require "net/http"
require "timeout"
require "uri"

module MusicMetadata
  class SpotifySource
    TOKEN_URL = URI("https://accounts.spotify.com/api/token")
    TRACK_BASE_URL = "https://api.spotify.com/v1/tracks/"

    def initialize(track, deadline: nil)
      @track = track
      @deadline = deadline
    end

    def call
      return skipped unless configured?

      payload = track_payload
      SourceResult.new(
        source: "spotify",
        claims: claims_from(payload),
        metadata: { isrc: payload.dig("external_ids", "isrc").presence },
        error: nil
      )
    rescue StandardError => e
      SourceResult.new(source: "spotify", claims: [], metadata: {}, error: "Spotify: #{e.message}")
    end

    private

    def configured?
      ENV["SPOTIFY_CLIENT_ID"].present? && ENV["SPOTIFY_CLIENT_SECRET"].present?
    end

    def track_payload
      raise "track has no Spotify ID" if @track.spotify_id.blank?

      token_request = Net::HTTP::Post.new(TOKEN_URL)
      token_request.set_form_data(grant_type: "client_credentials")
      token_request.basic_auth(ENV.fetch("SPOTIFY_CLIENT_ID"), ENV.fetch("SPOTIFY_CLIENT_SECRET"))
      token = json_response(TOKEN_URL, token_request).fetch("access_token")

      uri = URI("#{TRACK_BASE_URL}#{@track.spotify_id}")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"
      json_response(uri, request)
    end

    def claims_from(payload)
      source_url = payload.dig("external_urls", "spotify") || @track.external_url || "https://open.spotify.com/track/#{@track.spotify_id}"
      source_identifier = @track.spotify_id
      album = payload["album"] || {}

      [
        claim(
          "isrc",
          payload.dig("external_ids", "isrc"),
          "Spotify recording identifier",
          source_identifier,
          source_url,
          scope: "recording"
        ),
        claim(
          "release_date",
          album["release_date"],
          "Spotify album release (may be a reissue)",
          source_identifier,
          source_url,
          scope: "spotify_album_release",
          release_date_precision: album["release_date_precision"]
        ),
        claim(
          "release_title",
          album["name"],
          "Spotify album",
          source_identifier,
          source_url,
          scope: "spotify_album_release"
        ),
        claim(
          "release_position",
          [ payload["disc_number"], payload["track_number"] ].compact.join("-").presence,
          "Disc-track position on this Spotify album",
          source_identifier,
          source_url,
          scope: "spotify_album_release"
        )
      ].compact
    end

    def claim(field, text, context, source_identifier, source_url, extra = {})
      return if text.blank?

      {
        source_identifier: source_identifier,
        source_url: source_url,
        field: field,
        value: {
          "text" => text.to_s,
          "comparison" => text.to_s,
          "context" => context
        }.merge(extra.stringify_keys),
        match_confidence: "spotify_id"
      }
    end

    def json_response(uri, request)
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
      SourceResult.new(source: "spotify", claims: [], metadata: {}, skipped: true, error: nil)
    end
  end
end
