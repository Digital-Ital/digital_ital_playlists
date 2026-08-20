# frozen_string_literal: true

# Recovery draft for Digital Ital Crates.
#
# This restores 110 confirmed Spotify playlists without deleting any database
# records. Spotify is the source for metadata; category memberships below are
# limited to ones confirmed by the public crawl or exact live-playlist recovery.
# The initial 103 IDs came from the zelou2 profile. A Spotify account search then
# recovered the six historical Rap Period playlists and Cannabis Vol.9 that were
# absent from that profile listing. The missing Political Rap playlist was
# already among the 103 IDs; it needed its confirmed Political Crates link.
#
# Run from the Rails app:
#   ONLY=7hlunDhw82b535yN0G3qBv bin/rails runner db/recover_playlists_from_spotify.rb
#   APPLY=true bin/rails runner db/recover_playlists_from_spotify.rb
#
# Restore only the eight later-confirmed playlists/category links:
#   ONLY=3uFZgQMHNKOPrJ5CaqfUxj,5Wk94ntSegv7p9kfV6izOC,0tTWnuY0e3kCxdHkb7a3Np,49cVTDQoyb7wmAowLZEEBL,13DnHAQsl2Vc9TTdV3GmqR,6iWIiK7uKh3vJ78GdMgXK1,5DOE2RYR6OdjjRRZjUMfmi,7c2X4bajCe2r81ITmfgOsu APPLY=true bin/rails runner db/recover_playlists_from_spotify.rb
#
# By default this is a read-only dry run. It still calls Spotify so that it can
# validate the live metadata. APPLY=true is required for any database change.
# The run is idempotent: existing playlists are matched by canonical Spotify URL,
# no playlists or category links are deleted, and duplicate links are avoided.
# Track records are intentionally not imported here. The normal Spotify updater
# imports them afterward and calculates duration from the stored track rows.

require "json"
require "net/http"
require "uri"

APPLY = ENV.fetch("APPLY", "false").casecmp?("true")

PLAYLIST_IDS = %w[
  6v87eGDtz1YgIVioENw4jE 1ozTBerDyYQEXUKk0ptfto 7hlunDhw82b535yN0G3qBv
  1yN5oW0TVl56TS1w3WFOkz 0jv47FLQuUw0XWgv39GlQq 4vEfGk3mSmFPSnzEX3PI1q
  2Z7g9TLHE4zkcJane9gFYV 5pj2RAMS3w2Jd7nv1eSpG1 3YhzFVJxvdcyaqQ1YdOXY5
  6r5kAVbYF9zHPxASnJ0foM 0AjJkuiM4lAG9UeQQjyl0y 7iBloSyfGm7cECz23IRsfI
  15w1hjIcW49F6fZZY2KyVP 3q5NjSD1xBGp3P0L0Tltdm 60eEpJej6Y5alBTaZVlp5x
  3M2Z7DprROYIPJRqdui7GD 5DOE2RYR6OdjjRRZjUMfmi 4WNdI3I3fN0m4kqs5jbVI2
  0dD898TSMmT4V9D4iSxab9 5NPdHv6YMCxLpaZMFT7wQr 4SUbLE5DngsGAKCRx7TJJo
  4NEVixF4JRRxQuPl7mQu8B 73Ct4LCwZrfLfeDDg5OJzn 1vtdDtXevRsvDBj0kfn1na
  2GfHsEV9RSEaoGuI1XXq5x 4UhECCOv0nQ04xVBOOVoWN 1jjxhhvG1K5qbu0EpCxOHF
  25CAvbkCKLJmTshliV5XN6 2Q06sElqOYP61OXHhVgTmp 1SYu2anKUu77Lk7sTAf5Ez
  10AmYwBiUbKAEiP518Z057 0loFpQIgoBoyWdlNAKbBbJ 2BnEGdXBREWyOxrIIBjTdH
  2yizDFqp3w4ZdXHwgrM4MY 2Gx9b6lsvcoazikljIT8az 1lIya9jvQknFnHTpLwMDPr
  5lHM2RdDtaT6mkd7qhJ4CQ 2BOeyS5qsT9OnXAKFLtlzk 04Sprhgsr6eBAeU6idzNj9
  5BB8PRZ2tv6inaqBfKScNE 5KkOHmwYd0B1Lt9OECWf8a 2HH9NphuSnbwpKZJWCN06v
  43JLpZ5Hr5nVEGq7J8AFBx 32AuSEyicxUH14FqmFn6pi 7n0ZvBbyN8JmfnvKKiCBfJ
  1mPIYzOi8BnVYGibOLbpUd 5g55jZOJ6wij9ulXqkPYGE 4mctX4h7urnFl9fHAFS6DL
  1Mn0v86NdcmxkXcqK2E01E 4E355DKlGcHYtChwLAvTvw 3P0jPatgUYEjiW75Shy0WR
  1gm3vYJ7ognkbG1rR76GMj 1BgZCWZs7dLIzgG1cD46kX 1JdR8pXJKmR9ytka0mqToP
  4xGbQVEqSjE0k4z1kXPsS3 34KSUETfYDC98ejrCxWDQV 01DowoEWHeP9JSUxNibwfE
  1netcF6c0IfdhTqarX0U2b 5gB6ROA8iX2pfPcBf7WmwG 0iu4uhlowIxqI3wtxzhGbM
  5aRnqs7dalbYVHIEP9g32v 2iTK5OeqfErlHMFv0a8FA2 5m0ekEhgM9WqgRhN6cOkt0
  1jept9IheZxIxv6djzulst 0sLOx14Sj3Zt3kNPJtBjZt 7KEoifgX4Vtp8A52k7pKrT
  1fRizm7gZUCQuYx2LAnW8t 1H0jp0CMtVTGvPGlWphXWl 3lCcYM0PWrMPcafCLJ2nEY
  2O3fYGQs16E9SkoV4BXjfE 0vUZGsipJOwNKjWfROyut2 4QwX5BuDK2FRY6Z7UpaGMU
  0WOrgEC98J5ydnELgMRnCD 29X61w2lgaPJi89enSGri0 6GH8iJZUJdZ4Qwmz00SQYx
  6k7boKARlR3uoyDTlQ3P5l 6XDLhXJwM71KgqXR91sg4S 2hOBfzn4sAPJAJmM8T09T1
  1WRG1mgWJZkgcDYNLIUD6b 2d6AFCYHyVjdD3MwEIwotN 5ExsNzQupfOaGj9TQpbhmn
  47zCL1Z7WI4hojc3vBLmyL 2pWcZ4mHz4Rdp67opA9850 36kztdHYOI4ptDcGsQpBq8
  34JO9NAjwYW0xJSsTVBIq6 1bmtnp5ZOLhBLqrijs3dbE 2QLkxyps3X0TxZDkXmj1mU
  6sTPQJUGic5qpNHFZ9Xx5i 0zmEpyxm9wsBNnFePfKcis 1nq0EBgWDRek9dq36odivW
  3aAgERIXC01lfOt4mPa9hc 2i3ZifWKNbdfkh6MQXHOA4 7HjnuPJGk0CsGyp1GFxMxW
  6pfLl65uPrGCz1etAGNzFK 7BtcIaj1AeL8QjHNzV4AC7 3j7JCUSTwhglfjU0i3mTEU
  46YcGaKfClY3llAbYCWmvJ 1gGnOiBpxdgetiiV1x82VI 04kPKjefQG2ZqO5ar2f6JD
  5A0DxHZVowRh3h4eVWWncL 7Giwctx8AlL0Uee037BI41 7GVn20eILPAFrVbqMZi8hL
  74o71a1RFeNJqU9Hq4L2uy 3uFZgQMHNKOPrJ5CaqfUxj 5Wk94ntSegv7p9kfV6izOC
  0tTWnuY0e3kCxdHkb7a3Np 49cVTDQoyb7wmAowLZEEBL 13DnHAQsl2Vc9TTdV3GmqR
  6iWIiK7uKh3vJ78GdMgXK1 7c2X4bajCe2r81ITmfgOsu
].freeze

raise "Expected 110 unique Spotify playlist IDs" unless PLAYLIST_IDS.uniq.length == 110

CATEGORY_MEMBERSHIPS = Hash.new { |hash, key| hash[key] = [] }
add_category = lambda do |category_name, playlist_ids|
  playlist_ids.each { |playlist_id| CATEGORY_MEMBERSHIPS[playlist_id] << category_name }
end

# 14 crawl-confirmed assignments: 12 Reggae cards plus the two French Dubwise cards.
add_category.call "Main Reggae (Vocal) Branch", %w[
  43JLpZ5Hr5nVEGq7J8AFBx 32AuSEyicxUH14FqmFn6pi 7n0ZvBbyN8JmfnvKKiCBfJ
  1mPIYzOi8BnVYGibOLbpUd 5g55jZOJ6wij9ulXqkPYGE 4mctX4h7urnFl9fHAFS6DL
  1Mn0v86NdcmxkXcqK2E01E 4E355DKlGcHYtChwLAvTvw 3P0jPatgUYEjiW75Shy0WR
  1gm3vYJ7ognkbG1rR76GMj 1BgZCWZs7dLIzgG1cD46kX 1JdR8pXJKmR9ytka0mqToP
  73Ct4LCwZrfLfeDDg5OJzn 1vtdDtXevRsvDBj0kfn1na
]

# 16 crawl-confirmed assignments: 11 Sound System cards, the two French
# Dubwise cards, and Cannabis Vols. 1–3 (which are deliberately dual-category).
add_category.call "Rub-a-Dub / Sound System Branch", %w[
  0WOrgEC98J5ydnELgMRnCD 29X61w2lgaPJi89enSGri0 6GH8iJZUJdZ4Qwmz00SQYx
  6k7boKARlR3uoyDTlQ3P5l 6XDLhXJwM71KgqXR91sg4S 2hOBfzn4sAPJAJmM8T09T1
  1WRG1mgWJZkgcDYNLIUD6b 2d6AFCYHyVjdD3MwEIwotN 5ExsNzQupfOaGj9TQpbhmn
  36kztdHYOI4ptDcGsQpBq8 2QLkxyps3X0TxZDkXmj1mU 73Ct4LCwZrfLfeDDg5OJzn
  1vtdDtXevRsvDBj0kfn1na 25CAvbkCKLJmTshliV5XN6 2Q06sElqOYP61OXHhVgTmp
  1SYu2anKUu77Lk7sTAf5Ez
]

# The crawl contained Vols. 1–10; the newer Vols. 12–16 are intentionally left
# uncategorized rather than inferred from their names.
add_category.call "Dub & Instrumental Reggae Branch", %w[
  1netcF6c0IfdhTqarX0U2b 5gB6ROA8iX2pfPcBf7WmwG 0iu4uhlowIxqI3wtxzhGbM
  5aRnqs7dalbYVHIEP9g32v 2iTK5OeqfErlHMFv0a8FA2 5m0ekEhgM9WqgRhN6cOkt0
  1jept9IheZxIxv6djzulst 0sLOx14Sj3Zt3kNPJtBjZt 7KEoifgX4Vtp8A52k7pKrT
  1fRizm7gZUCQuYx2LAnW8t
]

add_category.call "Political Crates", %w[
  0zmEpyxm9wsBNnFePfKcis 1nq0EBgWDRek9dq36odivW 3aAgERIXC01lfOt4mPa9hc
  2i3ZifWKNbdfkh6MQXHOA4 7HjnuPJGk0CsGyp1GFxMxW 6pfLl65uPrGCz1etAGNzFK
  3M2Z7DprROYIPJRqdui7GD 5DOE2RYR6OdjjRRZjUMfmi
]

# Six historical Rap Period cards were recovered by exact live Spotify search.
add_category.call "Rap Period Crates", %w[
  7hlunDhw82b535yN0G3qBv 1yN5oW0TVl56TS1w3WFOkz 0jv47FLQuUw0XWgv39GlQq
  4vEfGk3mSmFPSnzEX3PI1q 3uFZgQMHNKOPrJ5CaqfUxj 5Wk94ntSegv7p9kfV6izOC
  0tTWnuY0e3kCxdHkb7a3Np 49cVTDQoyb7wmAowLZEEBL 13DnHAQsl2Vc9TTdV3GmqR
  6iWIiK7uKh3vJ78GdMgXK1
]

add_category.call "Lyrical Rap Branch", %w[
  7hlunDhw82b535yN0G3qBv 1yN5oW0TVl56TS1w3WFOkz 0jv47FLQuUw0XWgv39GlQq
  4vEfGk3mSmFPSnzEX3PI1q 2Z7g9TLHE4zkcJane9gFYV 5pj2RAMS3w2Jd7nv1eSpG1
  3YhzFVJxvdcyaqQ1YdOXY5 0AjJkuiM4lAG9UeQQjyl0y 7iBloSyfGm7cECz23IRsfI
  15w1hjIcW49F6fZZY2KyVP 3q5NjSD1xBGp3P0L0Tltdm 60eEpJej6Y5alBTaZVlp5x
  3M2Z7DprROYIPJRqdui7GD
]

# Cannabis Vol.9 was recovered by exact live Spotify search.
add_category.call "Cannabis Crates", %w[
  25CAvbkCKLJmTshliV5XN6 2Q06sElqOYP61OXHhVgTmp 1SYu2anKUu77Lk7sTAf5Ez
  0loFpQIgoBoyWdlNAKbBbJ 2yizDFqp3w4ZdXHwgrM4MY 1lIya9jvQknFnHTpLwMDPr
  2HH9NphuSnbwpKZJWCN06v 7c2X4bajCe2r81ITmfgOsu
]

add_category.call "Hip-Hop Beats / Instrumentals", %w[6r5kAVbYF9zHPxASnJ0foM]

unknown_ids = CATEGORY_MEMBERSHIPS.keys - PLAYLIST_IDS
raise "Category map contains unknown Spotify IDs: #{unknown_ids.join(', ')}" if unknown_ids.any?

class SpotifyRecoveryClient
  TOKEN_URI = URI("https://accounts.spotify.com/api/token")
  PLAYLIST_FIELDS = "name,description,images,followers,tracks(total)"

  def initialize
    @client_id = ENV.fetch("SPOTIFY_CLIENT_ID")
    @client_secret = ENV.fetch("SPOTIFY_CLIENT_SECRET")
    @access_token = fetch_access_token
  end

  def playlist_metadata(playlist_id)
    fields = URI.encode_www_form_component(PLAYLIST_FIELDS)
    playlist = get_json("https://api.spotify.com/v1/playlists/#{playlist_id}?fields=#{fields}")
    tracks = playlist.fetch("tracks", {})

    {
      title: playlist.fetch("name"),
      description: sanitize_description(playlist["description"]),
      cover_image_url: playlist.fetch("images", []).first&.fetch("url", nil),
      track_count: tracks.fetch("total", 0).to_i,
      followers_count: playlist.dig("followers", "total").to_i
    }
  end

  private

  def fetch_access_token
    request = Net::HTTP::Post.new(TOKEN_URI)
    request.set_form_data(grant_type: "client_credentials")
    request.basic_auth(@client_id, @client_secret)
    response = Net::HTTP.start(TOKEN_URI.host, TOKEN_URI.port, use_ssl: true, open_timeout: 15, read_timeout: 60) do |http|
      http.request(request)
    end

    raise "Spotify token request failed (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).fetch("access_token")
  end

  def get_json(url)
    last_error = nil

    5.times do |attempt|
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@access_token}"
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) do |http|
        http.request(request)
      end

      return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

      last_error = "Spotify request failed (HTTP #{response.code}): #{response.body.to_s[0, 200]}"
      retry_after = response["Retry-After"].to_i
      pause = retry_after.positive? ? retry_after : (2**attempt)
      sleep(pause) if response.code.to_i == 429 || response.code.to_i >= 500
      break unless response.code.to_i == 429 || response.code.to_i >= 500
    end

    raise last_error || "Spotify request failed"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError => error
    raise "Spotify connection failed: #{error.message}"
  end

  def sanitize_description(description)
    description.to_s.gsub(/<[^>]*>/, "").presence
  end

end

requested_ids = ENV.fetch("ONLY", "").split(",").map(&:strip).reject(&:blank?)
target_ids = requested_ids.presence || PLAYLIST_IDS
unknown_requested_ids = target_ids - PLAYLIST_IDS
raise "ONLY contains IDs outside the recovery inventory: #{unknown_requested_ids.join(', ')}" if unknown_requested_ids.any?

category_names = CATEGORY_MEMBERSHIPS.values.flatten.uniq
categories_by_name = Category.where(name: category_names).index_by(&:name)
missing_categories = category_names - categories_by_name.keys
raise "Missing recovery categories: #{missing_categories.join(', ')}" if missing_categories.any?

client = SpotifyRecoveryClient.new
results = Hash.new(0)
failures = []

puts "#{APPLY ? 'Applying' : 'Dry run'} Spotify recovery for #{target_ids.length} playlist(s)..."

target_ids.each_with_index do |spotify_id, index|
  spotify_url = "https://open.spotify.com/playlist/#{spotify_id}"

  begin
    metadata = client.playlist_metadata(spotify_id)
    raise "Spotify returned zero tracks" unless metadata[:track_count].positive?

    playlist = Playlist.find_or_initialize_by(spotify_url: spotify_url)
    created = playlist.new_record?
    playlist.assign_attributes(metadata.merge(last_updated_at: Time.current))
    playlist.position ||= PLAYLIST_IDS.index(spotify_id).to_i + 1
    category_names_for_playlist = CATEGORY_MEMBERSHIPS.fetch(spotify_id, [])

    if APPLY
      Playlist.transaction do
        playlist.save!
        category_names_for_playlist.each do |category_name|
          category = categories_by_name.fetch(category_name)
          playlist.categories << category unless playlist.categories.exists?(category.id)
        end
      end
    end

    results[created ? :created : :updated] += 1
    category_label = category_names_for_playlist.presence&.join(" + ") || "uncategorized (not inferred)"
    puts "#{index + 1}/#{target_ids.length} #{created ? 'create' : 'update'}: #{metadata[:title]} [#{category_label}]"
  rescue StandardError => error
    failures << [ spotify_id, error.message ]
    puts "#{index + 1}/#{target_ids.length} FAILED #{spotify_id}: #{error.message}"
  end
end

categorized_count = target_ids.count { |playlist_id| CATEGORY_MEMBERSHIPS.key?(playlist_id) }
assignment_count = target_ids.sum { |playlist_id| CATEGORY_MEMBERSHIPS.fetch(playlist_id, []).length }
puts "\n#{APPLY ? 'Applied' : 'Would apply'} #{results[:created]} new and #{results[:updated]} existing playlist record(s)."
puts "Crawl-confirmed category coverage: #{categorized_count}/#{target_ids.length} playlists, #{assignment_count} assignment(s)."

if failures.any?
  puts "#{failures.length} playlist(s) failed and can be retried safely with ONLY=<comma-separated IDs>:"
  failures.each { |spotify_id, message| puts "- #{spotify_id}: #{message}" }
  exit 1
end

puts APPLY ? "Recovery complete. No playlists or category links were deleted." : "Dry run complete. Re-run with APPLY=true to save."

