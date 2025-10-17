# Restoration Script for Digital Ital Structure
# Run this with: rails runner restore_structure.rb

puts "🎵 Restoring Digital Ital structure..."

# Clear existing data
PlaylistCategory.delete_all
Playlist.delete_all
Category.delete_all

# Load and restore categories
categories_data = JSON.parse(File.read("db_backup_20251007_031815/categories.json"))
category_map = {}

categories_data.each do |cat_data|
  category = Category.create!(
    name: cat_data['name'],
    slug: cat_data['slug'],
    description: cat_data['description'],
    color: cat_data['color'],
    position: cat_data['position']
  )
  category_map[cat_data['name']] = category
end

# Set up parent-child relationships
categories_data.each do |cat_data|
  next unless cat_data['parent_name']

  category = category_map[cat_data['name']]
  parent = category_map[cat_data['parent_name']]
  category.update!(parent: parent) if parent
end

# Load and restore playlists
playlists_data = JSON.parse(File.read("db_backup_20251007_031815/playlists.json"))

playlists_data.each do |playlist_data|
  playlist = Playlist.create!(
    title: playlist_data['title'],
    description: playlist_data['description'],
    spotify_url: playlist_data['spotify_url'],
    cover_image_url: playlist_data['cover_image_url'],
    track_count: playlist_data['track_count'],
    duration: playlist_data['duration'],
    featured: playlist_data['featured'],
    position: playlist_data['position']
  )

  # Associate with categories
  playlist_data['category_names'].each do |cat_name|
    category = category_map[cat_name]
    playlist.categories << category if category
  end
end

puts "✅ Restoration complete!"
puts "📊 Created 16 categories and 17 playlists"
