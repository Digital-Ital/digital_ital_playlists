# Rebuild the eight confirmed main categories for Digital Ital Crates.
#
# Run with:
#   bin/rails runner db/restore_main_categories.rb
#
# WARNING: This removes every category and every playlist-to-category link.
# It does not delete playlists, tracks, or analytics data.
#
# The names and emojis are recovered from the public site. The colors and
# Tailwind gradients are a faithful reconstructed palette because the original
# raw style strings existed only in the deleted database.

categories = [
  {
    name: "Main Reggae (Vocal) Branch",
    slug: "main-reggae-vocal-branch",
    emoji: "🎶",
    family_emoji: "🌴",
    color: "#22C55E",
    family_color: "from-green-600/80 to-yellow-600/80"
  },
  {
    name: "Rub-a-Dub / Sound System Branch",
    slug: "rub-a-dub-sound-system-branch",
    emoji: "📝",
    family_emoji: "🎤",
    color: "#F59E0B",
    family_color: "from-amber-600/80 to-orange-700/80"
  },
  {
    name: "Dub & Instrumental Reggae Branch",
    slug: "dub-instrumental-reggae-branch",
    emoji: "🔊",
    family_emoji: "🔊",
    color: "#06B6D4",
    family_color: "from-cyan-700/80 to-blue-700/80"
  },
  {
    name: "Political Crates",
    slug: "political-crates",
    emoji: "🗣️",
    family_emoji: "✊",
    color: "#A855F7",
    family_color: "from-purple-700/60 to-purple-600/60"
  },
  {
    name: "Rap Period Crates",
    slug: "rap-period-crates",
    emoji: "🎤",
    family_emoji: "🎤",
    color: "#EF4444",
    family_color: "from-red-600/80 to-orange-600/80"
  },
  {
    name: "Lyrical Rap Branch",
    slug: "lyrical-rap-branch",
    emoji: "📝",
    family_emoji: "📝",
    color: "#EC4899",
    family_color: "from-rose-700/80 to-fuchsia-700/80"
  },
  {
    name: "Cannabis Crates",
    slug: "cannabis-crates",
    emoji: "🌿",
    family_emoji: "💨",
    color: "#84CC16",
    family_color: "from-green-700/60 to-lime-600/60"
  },
  {
    name: "Hip-Hop Beats / Instrumentals",
    slug: "hip-hop-beats-instrumentals",
    emoji: "🔊",
    family_emoji: "🔊",
    color: "#3B82F6",
    family_color: "from-indigo-700/80 to-sky-700/80"
  }
]

ActiveRecord::Base.transaction do
  PlaylistCategory.delete_all
  Category.update_all(parent_id: nil)
  Category.delete_all

  categories.each_with_index do |attributes, index|
    category = Category.create!(
      name: attributes.fetch(:name),
      slug: attributes.fetch(:slug),
      emoji: attributes.fetch(:emoji),
      family_emoji: attributes.fetch(:family_emoji),
      color: attributes.fetch(:color),
      family_color: attributes.fetch(:family_color),
      is_main_family: true,
      position: index + 1,
      display_order: index + 1,
      parent: nil
    )

    puts "✓ Created: #{category.name}"
  end
end

puts "Rebuilt #{categories.length} main categories."
