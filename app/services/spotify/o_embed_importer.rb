require "open-uri"
require "json"

module Spotify
  class OEmbedImporter
    OEMBED_ENDPOINT = "https://open.spotify.com/oembed"

    def initialize(spotify_url)
      @spotify_url = spotify_url
    end

  def call
    raise ArgumentError, "Invalid Spotify URL" unless valid_spotify_url?
    
    encoded_url = URI.encode_www_form_component(@spotify_url)
    url = URI.parse("#{OEMBED_ENDPOINT}?url=#{encoded_url}")
    
    # Validate that we're only making requests to Spotify's oEmbed endpoint
    raise ArgumentError, "Invalid oEmbed endpoint" unless url.host == "open.spotify.com"
    
    json = URI.open(url, read_timeout: 5).read
    data = JSON.parse(json)

      # oEmbed returns limited fields; map what we can.
      {
        title: data["title"],
        thumbnail_url: data["thumbnail_url"],
        html: data["html"]
      }
    end
  end

  private

  def valid_spotify_url?
    @spotify_url.to_s.match?(/^https:\/\/open\.spotify\.com\/playlist\/[a-zA-Z0-9]+/)
  end
end
