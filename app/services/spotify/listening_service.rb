require "json"
require "net/http"
require "securerandom"
require "uri"

module Spotify
  class ListeningService
    class ConfigurationError < StandardError; end
    class ApiError < StandardError; end

    TOKEN_URL = URI("https://accounts.spotify.com/api/token")
    AUTHORIZE_URL = "https://accounts.spotify.com/authorize"
    CURRENTLY_PLAYING_URL = URI("https://api.spotify.com/v1/me/player/currently-playing")
    RECENTLY_PLAYED_URL = URI("https://api.spotify.com/v1/me/player/recently-played")

    SCOPES = %w[
      user-read-currently-playing
      user-read-playback-state
      user-read-recently-played
    ].freeze

    def initialize
      @client_id = ENV["SPOTIFY_CLIENT_ID"].to_s
      @client_secret = ENV["SPOTIFY_CLIENT_SECRET"].to_s
      @refresh_token = ENV["SPOTIFY_LISTENING_REFRESH_TOKEN"].to_s
      @redirect_uri = ENV["SPOTIFY_LISTENING_REDIRECT_URI"].to_s
    end

    def authorization_ready?
      @client_id.present? && @client_secret.present? && @redirect_uri.present?
    end

    def connected?
      authorization_ready? && @refresh_token.present?
    end

    def authorization_url(state:)
      raise ConfigurationError, "Set SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET, and SPOTIFY_LISTENING_REDIRECT_URI first." unless authorization_ready?

      uri = URI(AUTHORIZE_URL)
      uri.query = URI.encode_www_form(
        response_type: "code",
        client_id: @client_id,
        redirect_uri: @redirect_uri,
        scope: SCOPES.join(" "),
        state: state,
        show_dialog: "true"
      )
      uri.to_s
    end

    def exchange_code(code)
      raise ConfigurationError, "Spotify listening OAuth is not configured." unless authorization_ready?

      response = token_request(
        grant_type: "authorization_code",
        code: code,
        redirect_uri: @redirect_uri
      )

      refresh_token = response["refresh_token"].to_s
      raise ApiError, "Spotify did not return a refresh token. Re-authorize and approve the requested access." if refresh_token.empty?

      refresh_token
    end

    def currently_playing
      return nil unless connected?

      response = get(CURRENTLY_PLAYING_URL, access_token)
      return nil if response.code.to_i == 204

      payload = parse_response(response)
      return nil unless payload["item"]&.dig("type") == "track"

      track_payload(payload["item"]).merge(
        is_playing: payload["is_playing"],
        progress_ms: payload["progress_ms"]
      )
    end

    def recently_played(limit: 10)
      return [] unless connected?

      uri = RECENTLY_PLAYED_URL.dup
      uri.query = URI.encode_www_form(limit: [[limit.to_i, 1].max, 50].min)

      payload = parse_response(get(uri, access_token))
      payload.fetch("items", []).filter_map do |item|
        track = item["track"]
        next unless track&.dig("type") == "track"

        track_payload(track).merge(played_at: item["played_at"])
      end
    end

    private

    def access_token
      @access_token ||= token_request(
        grant_type: "refresh_token",
        refresh_token: @refresh_token
      ).fetch("access_token")
    end

    def token_request(params)
      request = Net::HTTP::Post.new(TOKEN_URL)
      request.set_form_data(params)
      request.basic_auth(@client_id, @client_secret)

      response = request_uri(TOKEN_URL, request)
      parse_response(response)
    end

    def get(uri, token)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request_uri(uri, request, allow_no_content: true)
    end

    def request_uri(uri, request, allow_no_content: false)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
      return response if allow_no_content && response.code.to_i == 204
      return response if response.is_a?(Net::HTTPSuccess)

      retry_after = response["Retry-After"]
      retry_message = retry_after.present? ? " Try again in #{retry_after} seconds." : ""
      raise ApiError, "Spotify request failed (HTTP #{response.code}).#{retry_message}"
    end

    def parse_response(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      raise ApiError, "Spotify returned an unreadable response."
    end

    def track_payload(track)
      {
        spotify_id: track["id"],
        name: track["name"],
        artist: Array(track["artists"]).filter_map { |artist| artist["name"] }.join(", "),
        album: track.dig("album", "name"),
        image_url: track.dig("album", "images")&.first&.dig("url"),
        external_url: track.dig("external_urls", "spotify"),
        duration_ms: track["duration_ms"],
        album_track_number: track["track_number"]
      }
    end
  end
end
