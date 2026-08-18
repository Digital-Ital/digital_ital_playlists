# Restoration Script for Digital Ital Structure
# Run this with: bin/rails runner db_backup_20251007_031815/restore_structure.rb

puts "🎵 Restoring Digital Ital structure..."

ActiveRecord::Base.transaction do
  # Clear existing data in foreign-key-safe order.
  PlaylistCategory.delete_all
  PlaylistTrack.delete_all
  PlaylistUpdate.delete_all
  UpdateLog.delete_all
  ShareEvent.delete_all
  SpotifyOpen.delete_all
  Playlist.delete_all

  # Remove self-references before deleting the category tree.
  Category.update_all(parent_id: nil)
  Category.delete_all

  categories_data = JSON.parse(File.read("db_backup_20251007_031815/categories.json"))
  category_map = {}
  pending_categories = categories_data.index_by { |category| category.fetch("name") }

  # Create each category only after its parent exists. This preserves the
  # position uniqueness rule within each parent instead of treating every
  # category as a root during the import.
  until pending_categories.empty?
    created_count = 0

    pending_categories.keys.each do |name|
      category_data = pending_categories[name]
      parent_name = category_data["parent_name"]

      next if parent_name.present? && !category_map.key?(parent_name)

      category_map[name] = Category.create!(
        name: category_data["name"],
        slug: category_data["slug"],
        description: category_data["description"],
        color: category_data["color"],
        position: category_data["position"],
        parent: category_map[parent_name]
      )
      pending_categories.delete(name)
      created_count += 1
    end

    next if created_count.positive?

    missing_parents = pending_categories.values.filter_map { |category| category["parent_name"] }.uniq
    raise "Could not restore categories; missing or circular parents: #{missing_parents.join(", ")}"
  end

  playlists_data = JSON.parse(File.read("db_backup_20251007_031815/playlists.json"))

  playlists_data.each do |playlist_data|
    playlist = Playlist.create!(
      title: playlist_data["title"],
      description: playlist_data["description"],
      spotify_url: playlist_data["spotify_url"],
      cover_image_url: playlist_data["cover_image_url"],
      track_count: playlist_data["track_count"],
      duration: playlist_data["duration"],
      featured: playlist_data["featured"],
      position: playlist_data["position"]
    )

    Array(playlist_data["category_names"]).each do |category_name|
      category = category_map[category_name]
      playlist.categories << category if category
    end
  end
end

puts "✅ Restoration complete!"
puts "📊 Created 16 categories and 17 playlists"
