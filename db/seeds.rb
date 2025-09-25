# Digital Ital's List of Playlists - Sample Data

# Create Categories
categories_data = [
  { name: "Hip-Hop", color: "#FF6B6B", position: 1, description: "Lyrical mastery and beats that move the soul" },
  { name: "Reggae", color: "#4ECDC4", position: 2, description: "Roots, rock, reggae - the foundation of sound" },
  { name: "Dubwise Reggae", color: "#45B7D1", position: 3, description: "Echo chambers and bass lines that shake the earth" },
  { name: "Rock-Reggae", color: "#96CEB4", position: 4, description: "Where rock meets reggae in perfect harmony" },
  { name: "Rap-Reggae", color: "#FFEAA7", position: 5, description: "Fast flows over reggae riddims" },
  { name: "Political Songs", color: "#DDA0DD", position: 6, description: "Music with a message, songs for change" },
  { name: "Cannabis Songs", color: "#98D8C8", position: 7, description: "Herb-inspired tracks and green vibes" },
  { name: "Period Crates", color: "#F7DC6F", position: 8, description: "Deep cuts and rare finds from the vinyl vault" },
  { name: "Other Playlists & Requests", color: "#BB8FCE", position: 9, description: "Everything else and your requests" }
]

categories = categories_data.map do |cat_data|
  Category.find_or_create_by!(name: cat_data[:name]) do |category|
    category.color = cat_data[:color]
    category.position = cat_data[:position]
    category.description = cat_data[:description]
  end
end

# Sample Playlists
playlists_data = [
  # Hip-Hop
  {
    title: "Golden Era Classics: 90s Hip-Hop Masterpieces",
    description: "The golden age of hip-hop when lyrics ruled supreme and beats were crafted with vinyl samples. From Nas to Wu-Tang, this is where it all began.",
    category: "Hip-Hop",
    track_count: 25,
    duration: "1h 45m",
    featured: true,
    spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzp",
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8"
  },
  {
    title: "Underground Kings: Independent Hip-Hop Gems",
    description: "Raw, unfiltered hip-hop from the underground. These artists keep it real without the mainstream machine.",
    category: "Hip-Hop",
    track_count: 18,
    duration: "1h 12m",
    featured: false,
    spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzp",
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8"
  },
  
  # Reggae
  {
    title: "Roots & Culture: Classic Reggae Essentials",
    description: "The foundation of reggae music. Bob Marley, Peter Tosh, and the legends who built the sound that changed the world.",
    category: "Reggae",
    track_count: 30,
    duration: "2h 15m",
    featured: true,
    spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzp",
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8"
  },
  {
    title: "Modern Reggae Vibes: Contemporary Roots",
    description: "Today's reggae artists carrying the torch forward. Fresh sounds with deep roots.",
    category: "Reggae",
    track_count: 22,
    duration: "1h 38m",
    featured: false,
    spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzp",
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8"
  },
  
  # Dubwise Reggae
  {
    title: "Dub Sessions: Echo Chambers & Bass Lines",
    description: "King Tubby, Lee Perry, and the dub masters who created the sound of the future in the 70s.",
    category: "Dubwise Reggae",
    track_count: 20,
    duration: "1h 45m",
    featured: true,
    spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzp",
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8"
  },
  {
    title: "Digital Dub: Modern Sound System Culture",
    description: "Contemporary dub artists pushing the boundaries of bass and echo in the digital age.",
    category: "Dubwise Reggae",
    track_count: 16,
    duration: "1h 20m",
    featured: false,
    spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzp",
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8"
  },
  
  # Rock-Reggae
  {
    title: "Rock Steady: When Rock Met Reggae",
    description: "The perfect fusion of rock energy and reggae soul. From The Clash to Sublime, this is where genres collide beautifully.",
    category: "Rock-Reggae",
    track_count: 24,
    duration: "1h 52m",
    featured: true,
    spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzp",
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8"
  },
  
  # Rap-Reggae
  {
    title: "Rap-Reggae Fusion: Fast Flows Over Riddims",
    description: "Where hip-hop meets reggae in perfect harmony. Dancehall meets rap in this high-energy collection.",
    category: "Rap-Reggae",
    track_count: 19,
    duration: "1h 25m",
    featured: false,
    spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzp",
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8"
  },
  
  # Political Songs
  {
    title: "Revolutionary Sounds: Music for Change",
    description: "Songs that speak truth to power. From Bob Marley's 'Get Up, Stand Up' to modern protest anthems.",
    category: "Political Songs",
    track_count: 21,
    duration: "1h 35m",
    featured: false,
    spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzp",
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8"
  },
  
  # Cannabis Songs
  {
    title: "Herb & Music: Green Vibes Only",
    description: "Songs celebrating the sacred herb. From reggae classics to modern cannabis anthems.",
    category: "Cannabis Songs",
    track_count: 17,
    duration: "1h 18m",
    featured: false,
    spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzp",
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8"
  },
  
  # Period Crates
  {
    title: "Vinyl Vault: Rare Finds & Deep Cuts",
    description: "Hidden gems from the crates. Rare tracks that never made it to the mainstream but deserve to be heard.",
    category: "Period Crates",
    track_count: 23,
    duration: "1h 48m",
    featured: false,
    spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzp",
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8"
  },
  {
    title: "B-Sides & Rarities: The Collector's Edition",
    description: "For the true music heads. B-sides, remixes, and rare tracks that showcase the artist's full range.",
    category: "Period Crates",
    track_count: 26,
    duration: "2h 5m",
    featured: false,
    spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzp",
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8"
  },
  
  # Other Playlists & Requests
  {
    title: "Listener Requests: Your Voice, My Curation",
    description: "Playlists created from your requests and suggestions. The community shapes the sound.",
    category: "Other Playlists & Requests",
    track_count: 20,
    duration: "1h 30m",
    featured: false,
    spotify_url: "https://open.spotify.com/playlist/37i9dQZF1DX186v583rmzp",
    cover_image_url: "https://i.scdn.co/image/ab67706f00000002f1b2b9b8b8b8b8b8b8b8b8b8"
  }
]

# Create Playlists
playlists_data.each do |playlist_data|
  category = Category.find_by(name: playlist_data[:category])
  next unless category
  
  Playlist.find_or_create_by!(title: playlist_data[:title]) do |playlist|
    playlist.description = playlist_data[:description]
    playlist.category = category
    playlist.track_count = playlist_data[:track_count]
    playlist.duration = playlist_data[:duration]
    playlist.featured = playlist_data[:featured]
    playlist.spotify_url = playlist_data[:spotify_url]
    playlist.cover_image_url = playlist_data[:cover_image_url]
    playlist.position = rand(1..100)
  end
end

puts "✅ Created #{Category.count} categories"
puts "✅ Created #{Playlist.count} playlists"
puts "🎵 Digital Ital's List of Playlists is ready!"
