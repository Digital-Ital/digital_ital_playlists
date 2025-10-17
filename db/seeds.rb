# Digital Ital's List of Playlists - Hierarchical Categories

# Clear existing data in the correct order to avoid foreign key constraints
if defined?(PlaylistCategory)
  ActiveRecord::Base.connection.execute("DELETE FROM playlist_categories")
end
Playlist.destroy_all
Category.destroy_all

# Create hierarchical categories
reggae = Category.create!(name: "Reggae", color: "#4ECDC4", position: 1, description: "Roots, rock, reggae - the foundation of sound")
hip_hop = Category.create!(name: "Hip-Hop", color: "#FF6B6B", position: 2, description: "Lyrical mastery and beats that move the soul")
political = Category.create!(name: "Political Songs", color: "#DDA0DD", position: 3, description: "Music with a message, songs for change")
cannabis = Category.create!(name: "Cannabis Songs", color: "#98D8C8", position: 4, description: "Herb-inspired tracks and green vibes")

# Reggae children
Category.create!(name: "Dubwise Reggae", color: "#45B7D1", position: 1, description: "Echo chambers and bass lines that shake the earth", parent: reggae)
Category.create!(name: "Rock-Reggae", color: "#96CEB4", position: 2, description: "Where rock meets reggae in perfect harmony", parent: reggae)
Category.create!(name: "Rap-Reggae", color: "#FFEAA7", position: 3, description: "Fast flows over reggae riddims", parent: reggae)
Category.create!(name: "Reggae Period Crates", color: "#F7DC6F", position: 4, description: "Deep cuts and rare finds from the vinyl vault", parent: reggae)

# Hip-Hop children
Category.create!(name: "Rap Period Crates", color: "#F7DC6F", position: 1, description: "Deep cuts and rare finds from the vinyl vault", parent: hip_hop)
Category.create!(name: "Lyrical Hip-Hop Explorations", color: "#FF6B6B", position: 2, description: "Lyrical mastery and beats that move the soul", parent: hip_hop)

# Political children
Category.create!(name: "Reggae Political Crates", color: "#DDA0DD", position: 1, description: "Reggae with a message, songs for change", parent: political)
Category.create!(name: "Rap Political Crates", color: "#DDA0DD", position: 2, description: "Rap with a message, songs for change", parent: political)
Category.create!(name: "Other Political Crates", color: "#DDA0DD", position: 3, description: "Other political music, songs for change", parent: political)

# Cannabis children
Category.create!(name: "Reggae Cannabis Crates", color: "#98D8C8", position: 1, description: "Reggae herb-inspired tracks and green vibes", parent: cannabis)
Category.create!(name: "Rap Cannabis Crates", color: "#98D8C8", position: 2, description: "Rap herb-inspired tracks and green vibes", parent: cannabis)
Category.create!(name: "Other Cannabis Crates", color: "#98D8C8", position: 3, description: "Other herb-inspired tracks and green vibes", parent: cannabis)

    # Sample Playlists for each category
    playlists_data = [
      # Reggae
      { title: "Roots & Culture: Classic Reggae Essentials", description: "The foundation of reggae music. Bob Marley, Peter Tosh, and the legends who built the sound that changed the world.", category: "Reggae", track_count: 30, duration: "2h 15m", featured: true, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzp" },
      { title: "Modern Reggae Vibes: Contemporary Roots", description: "Today's reggae artists carrying the torch forward. Fresh sounds with deep roots.", category: "Reggae", track_count: 22, duration: "1h 38m", featured: false, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzq" },

      # Dubwise Reggae
      { title: "Dub Sessions: Echo Chambers & Bass Lines", description: "King Tubby, Lee Perry, and the dub masters who created the sound of the future in the 70s.", category: "Dubwise Reggae", track_count: 20, duration: "1h 45m", featured: true, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzr" },
      { title: "Digital Dub: Modern Sound System Culture", description: "Contemporary dub artists pushing the boundaries of bass and echo in the digital age.", category: "Dubwise Reggae", track_count: 16, duration: "1h 20m", featured: false, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzs" },

      # Rock-Reggae
      { title: "Rock Steady: When Rock Met Reggae", description: "The perfect fusion of rock energy and reggae soul. From The Clash to Sublime, this is where genres collide beautifully.", category: "Rock-Reggae", track_count: 24, duration: "1h 52m", featured: true, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzt" },

      # Rap-Reggae
      { title: "Rap-Reggae Fusion: Fast Flows Over Riddims", description: "Where hip-hop meets reggae in perfect harmony. Dancehall meets rap in this high-energy collection.", category: "Rap-Reggae", track_count: 19, duration: "1h 25m", featured: false, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzu" },

      # Reggae Period Crates
      { title: "Reggae Vinyl Vault: Rare Finds & Deep Cuts", description: "Hidden gems from the reggae crates. Rare tracks that never made it to the mainstream but deserve to be heard.", category: "Reggae Period Crates", track_count: 23, duration: "1h 48m", featured: false, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzv" },

      # Hip-Hop
      { title: "Golden Era Classics: 90s Hip-Hop Masterpieces", description: "The golden age of hip-hop when lyrics ruled supreme and beats were crafted with vinyl samples. From Nas to Wu-Tang, this is where it all began.", category: "Hip-Hop", track_count: 25, duration: "1h 45m", featured: true, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzw" },
      { title: "Underground Kings: Independent Hip-Hop Gems", description: "Raw, unfiltered hip-hop from the underground. These artists keep it real without the mainstream machine.", category: "Hip-Hop", track_count: 18, duration: "1h 12m", featured: false, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzx" },

      # Lyrical Hip-Hop Explorations
      { title: "Lyrical Mastery: Wordsmiths & Storytellers", description: "For the true lyricists. Complex flows, intricate wordplay, and storytelling that elevates the art form.", category: "Lyrical Hip-Hop Explorations", track_count: 21, duration: "1h 35m", featured: false, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzy" },

      # Rap Period Crates
      { title: "Rap Vinyl Vault: Rare Finds & Deep Cuts", description: "Hidden gems from the rap crates. Rare tracks that never made it to the mainstream but deserve to be heard.", category: "Rap Period Crates", track_count: 26, duration: "2h 5m", featured: false, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzz" },

      # Political Songs
      { title: "Revolutionary Sounds: Music for Change", description: "Songs that speak truth to power. From Bob Marley's 'Get Up, Stand Up' to modern protest anthems.", category: "Political Songs", track_count: 21, duration: "1h 35m", featured: false, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rma0" },

      # Reggae Political Crates
      { title: "Reggae Revolution: Political Reggae Classics", description: "Reggae with a message. Songs that speak truth to power and fight for justice.", category: "Reggae Political Crates", track_count: 18, duration: "1h 25m", featured: false, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rma1" },

      # Rap Political Crates
      { title: "Rap Revolution: Political Rap Classics", description: "Rap with a message. Songs that speak truth to power and fight for justice.", category: "Rap Political Crates", track_count: 19, duration: "1h 30m", featured: false, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rma2" },

      # Cannabis Songs
      { title: "Herb & Music: Green Vibes Only", description: "Songs celebrating the sacred herb. From reggae classics to modern cannabis anthems.", category: "Cannabis Songs", track_count: 17, duration: "1h 18m", featured: false, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rma3" },

      # Reggae Cannabis Crates
      { title: "Reggae Herb Vibes: Green Reggae Classics", description: "Reggae herb-inspired tracks and green vibes. The sacred herb meets the sacred sound.", category: "Reggae Cannabis Crates", track_count: 16, duration: "1h 15m", featured: false, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rma4" },

      # Rap Cannabis Crates
      { title: "Rap Herb Vibes: Green Rap Classics", description: "Rap herb-inspired tracks and green vibes. The sacred herb meets the sacred sound.", category: "Rap Cannabis Crates", track_count: 15, duration: "1h 10m", featured: false, spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rma5" }
    ]

# Create Playlists
playlists_data.each do |playlist_data|
  category = Category.find_by(name: playlist_data[:category])
  next unless category

  playlist = Playlist.create!(
    title: playlist_data[:title],
    description: playlist_data[:description],
    track_count: playlist_data[:track_count],
    duration: playlist_data[:duration],
    featured: playlist_data[:featured],
        spotify_url: playlist_data[:spotify_url],
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8",
    position: rand(1..100)
  )

  # Associate playlist with category using many-to-many relationship
  playlist.categories << category
end

    # Create Multi-Category Playlists for testing many-to-many relationships
    multi_category_playlists = [
      {
        title: "Dub Revolution: Political Dub Classics",
        description: "Dub music with a message - where deep bass meets deep thoughts. Political dub that speaks truth to power.",
        categories: [ "Dubwise Reggae", "Reggae Political Crates" ],
        track_count: 18,
        duration: "1h 32m",
        featured: true,
        spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rma6"
      },
      {
        title: "Rap & Herb: Lyrical Cannabis Vibes",
        description: "Where lyrical mastery meets herb culture. Complex flows celebrating the sacred plant.",
        categories: [ "Lyrical Hip-Hop Explorations", "Rap Cannabis Crates" ],
        track_count: 16,
        duration: "1h 25m",
        featured: false,
        spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rma7"
      },
      {
        title: "Revolutionary Sound System: Political Rap-Reggae Fusion",
        description: "The perfect fusion of political rap and reggae. Fast flows over revolutionary riddims.",
        categories: [ "Rap-Reggae", "Reggae Political Crates", "Rap Political Crates" ],
        track_count: 22,
        duration: "1h 45m",
        featured: true,
        spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rma8"
      },
      {
        title: "Vinyl Vault Classics: Rare Political & Cannabis Gems",
        description: "Deep cuts from the crates - rare political and cannabis tracks that never made it mainstream.",
        categories: [ "Reggae Period Crates", "Rap Period Crates", "Other Political Crates", "Other Cannabis Crates" ],
        track_count: 24,
        duration: "1h 58m",
        featured: false,
        spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rma9"
      },
      {
        title: "Green Revolution: Cannabis-Inspired Political Music",
        description: "Where the herb meets the message. Cannabis-inspired tracks with political consciousness.",
        categories: [ "Political Songs", "Cannabis Songs" ],
        track_count: 20,
        duration: "1h 38m",
        featured: false,
        spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmab"
      }
    ]

# Create Multi-Category Playlists
multi_category_playlists.each do |playlist_data|
  playlist = Playlist.create!(
    title: playlist_data[:title],
    description: playlist_data[:description],
    track_count: playlist_data[:track_count],
    duration: playlist_data[:duration],
    featured: playlist_data[:featured],
        spotify_url: playlist_data[:spotify_url],
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8",
    position: rand(1..100)
  )

  # Associate playlist with multiple categories
  playlist_data[:categories].each do |category_name|
    category = Category.find_by(name: category_name)
    playlist.categories << category if category
  end
end

puts "✅ Created #{Category.count} categories"
puts "✅ Created #{Playlist.count} playlists"
puts "🎵 Digital Ital's List of Playlists is ready!"
