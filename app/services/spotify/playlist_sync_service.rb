require "net/http"
require "uri"
require "json"

module Spotify
  class PlaylistSyncService
    TOKEN_URL = URI("https://accounts.spotify.com/api/token")

    def initialize(playlist)
      @playlist = playlist
      @client_id = ENV["SPOTIFY_CLIENT_ID"]
      @client_secret = ENV["SPOTIFY_CLIENT_SECRET"]
    end

    # Main sync method that returns full track details with added_at timestamps
    def sync
      raise ArgumentError, "SPOTIFY_CLIENT_ID/SECRET not configured" if @client_id.to_s.empty? || @client_secret.to_s.empty?

      playlist_id = @playlist.spotify_id
      raise ArgumentError, "Invalid Spotify playlist URL" unless playlist_id

      token = fetch_access_token
      spotify_data = fetch_playlist_with_tracks(playlist_id, token)

      {
        metadata: extract_metadata(spotify_data),
        tracks: extract_tracks(spotify_data, token)
      }
    end

    private

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

    def fetch_playlist_with_tracks(playlist_id, token)
      # Request playlist with all track fields including added_at and followers
      url = URI("https://api.spotify.com/v1/playlists/#{playlist_id}?fields=name,description,images,followers,tracks(items(added_at,track(id,name,artists,album,duration_ms,preview_url,external_urls)),total,next)")
      req = Net::HTTP::Get.new(url)
      req["Authorization"] = "Bearer #{token}"

      res = Net::HTTP.start(url.host, url.port, use_ssl: true) do |http|
        http.request(req)
      end

      raise "Spotify playlist error: #{res.code}" unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body)
    end

    def extract_metadata(spotify_data)
      {
        title: spotify_data["name"],
        description: sanitize_description(spotify_data["description"]),
        cover_image_url: (spotify_data["images"] || []).first&.dig("url"),
        track_count: spotify_data.dig("tracks", "total") || 0,
        followers_count: spotify_data.dig("followers", "total") || 0
      }
    end

    def extract_tracks(spotify_data, token)
      tracks = []
      items = spotify_data.dig("tracks", "items") || []
      
      # Process first page
      items.each_with_index do |item, index|
        track_data = extract_track_data(item, index)
        tracks << track_data if track_data
      end

      # Fetch remaining pages
      next_url = spotify_data.dig("tracks", "next")
      position_offset = items.size
      
      while next_url
        page_data = fetch_tracks_page(next_url, token)
        (page_data["items"] || []).each_with_index do |item, index|
          track_data = extract_track_data(item, position_offset + index)
          tracks << track_data if track_data
        end
        next_url = page_data["next"]
        position_offset += (page_data["items"] || []).size
      end

      tracks
    end

    def extract_track_data(item, position)
      track = item["track"]
      return nil unless track && track["id"]

      {
        spotify_id: track["id"],
        name: track["name"],
        artist: extract_artists(track["artists"]),
        album: track.dig("album", "name"),
        image_url: track.dig("album", "images")&.first&.dig("url"),
        duration_ms: track["duration_ms"],
        preview_url: track["preview_url"],
        external_url: track.dig("external_urls", "spotify"),
        added_at: item["added_at"] ? Time.parse(item["added_at"]) : Time.current,
        position: position
      }
    rescue => e
      Rails.logger.error "Failed to extract track data: #{e.message}"
      nil
    end

    def extract_artists(artists)
      return "Unknown Artist" unless artists&.any?
      artists.map { |a| a["name"] }.join(", ")
    end

    def fetch_tracks_page(next_url, token)
      url = URI(next_url)
      req = Net::HTTP::Get.new(url)
      req["Authorization"] = "Bearer #{token}"

      res = Net::HTTP.start(url.host, url.port, use_ssl: true) do |http|
        http.request(req)
      end

      raise "Spotify tracks page error: #{res.code}" unless res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body)
    end

    def sanitize_description(html)
      return nil if html.nil?
      # Spotify may return HTML; strip basic tags
      html.gsub(/<[^>]*>/, "")
    end
  end
end

