require "net/http"
require "uri"
require "json"

module Spotify
  class PlaylistImporter
    TOKEN_URL = URI("https://accounts.spotify.com/api/token")

    def initialize(spotify_url)
      @spotify_url = spotify_url
      @client_id = ENV["SPOTIFY_CLIENT_ID"]
      @client_secret = ENV["SPOTIFY_CLIENT_SECRET"]
    end

    def call
      raise ArgumentError, "SPOTIFY_CLIENT_ID/SECRET not configured" if @client_id.to_s.empty? || @client_secret.to_s.empty?

      playlist_id = extract_playlist_id(@spotify_url)
      raise ArgumentError, "Invalid Spotify playlist URL" unless playlist_id

      token = fetch_access_token
      playlist = fetch_playlist(playlist_id, token)

      # Sum duration across all pages for accurate total
      total_ms = sum_all_track_durations(playlist.dig("tracks"), token)

      {
        title: playlist["name"],
        description: sanitize_description(playlist["description"]),
        thumbnail_url: (playlist["images"] || []).first&.dig("url"),
        track_count: playlist.dig("tracks", "total") || tracks_items.size,
        duration: format_duration_ms(total_ms),
        spotify_url: @spotify_url
      }
    end

    private

    def extract_playlist_id(url)
      match = url.to_s.match(/playlist\/(\w+)/)
      match && match[1]
    end

    def fetch_access_token
      req = Net::HTTP::Post.new(TOKEN_URL)
      req.set_form_data({ grant_type: "client_credentials" })
      req.basic_auth(@client_id, @client_secret)

      res = Net::HTTP.start(TOKEN_URL.host, TOKEN_URL.port, use_ssl: true) do |http|
        http.request(req)
      end

      raise "Spotify token error: #{res.code}" unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body).fetch("access_token")
    end

    def fetch_playlist(playlist_id, token)
      # Include tracks to compute duration; limit 100 for first page and include pagination cursor
      url = URI("https://api.spotify.com/v1/playlists/#{playlist_id}?fields=name,description,images,tracks(items(track(duration_ms)),total,next)")
      req = Net::HTTP::Get.new(url)
      req["Authorization"] = "Bearer #{token}"

      res = Net::HTTP.start(url.host, url.port, use_ssl: true) do |http|
        http.request(req)
      end

      raise "Spotify playlist error: #{res.code}" unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body)
    end

    def sum_all_track_durations(tracks_obj, token)
      return 0 unless tracks_obj

      total_ms = 0
      # sum first page
      (tracks_obj["items"] || []).each do |item|
        total_ms += item.dig("track", "duration_ms").to_i
      end

      # follow pagination
      next_url = tracks_obj["next"]
      while next_url
        page = fetch_tracks_page(next_url, token)
        (page["items"] || []).each do |item|
          total_ms += item.dig("track", "duration_ms").to_i
        end
        next_url = page["next"]
      end

      total_ms
    end

    def fetch_tracks_page(next_url, token)
      url = URI(next_url)
      req = Net::HTTP::Get.new(url)
      req["Authorization"] = "Bearer #{token}"

      res = Net::HTTP.start(url.host, url.port, use_ssl: true) do |http|
        http.request(req)
      end

      raise "Spotify tracks page error: #{res.code}" unless res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body).fetch("tracks", JSON.parse(res.body)) rescue JSON.parse(res.body)
    end

    def format_duration_ms(ms)
      minutes = (ms / 1000) / 60
      hours = minutes / 60
      mins = minutes % 60
      if hours > 0
        "#{hours}h #{mins}m"
      else
        "#{mins}m"
      end
    end

    def sanitize_description(html)
      return nil if html.nil?
      # Spotify may return HTML; strip basic tags
      html.gsub(/<[^>]*>/, "")
    end
  end
end
