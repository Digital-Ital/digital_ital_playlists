require 'open-uri'
require 'json'

module Spotify
  class OEmbedImporter
    OEMBED_ENDPOINT = 'https://open.spotify.com/oembed'

    def initialize(spotify_url)
      @spotify_url = spotify_url
    end

    def call
      raise ArgumentError, 'Invalid Spotify URL' unless @spotify_url.to_s.match?(/spotify\.com\/playlist\//)
      url = URI.parse("#{OEMBED_ENDPOINT}?url=#{URI.encode_www_form_component(@spotify_url)}")
      json = URI.open(url, read_timeout: 5).read
      data = JSON.parse(json)

      # oEmbed returns limited fields; map what we can.
      {
        title: data['title'],
        thumbnail_url: data['thumbnail_url'],
        html: data['html']
      }
    end
  end
end


