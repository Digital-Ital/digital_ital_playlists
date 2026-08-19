# Restore the confirmed top-level category structure for Digital Ital Crates.
#
# Run with:
#   bin/rails runner db/restore_main_categories.rb
#
# This script is idempotent: it creates missing categories and updates matching
# slugs. It does not delete categories, playlists, tracks, or analytics data.

categories = [
  { name: "Main Reggae (Vocal) Branch", slug: "main-reggae-vocal-branch", emoji: "🌴", color: "#16A34A" },
  { name: "Rub-a-Dub / Sound System Branch", slug: "rub-a-dub-sound-system-branch", emoji: "🎤", color: "#F59E0B" },
  { name: "Dub & Instrumental Reggae Branch", slug: "dub-instrumental-reggae-branch", emoji: "🔊", color: "#0EA5E9" },
  { name: "Political Crates", slug: "political-crates", emoji: "✊", color: "#A855F7" },
  { name: "Rap Period Crates", slug: "rap-period-crates", emoji: "🎤", color: "#EF4444" },
  { name: "Lyrical Rap Branch", slug: "lyrical-rap-branch", emoji: "📝", color: "#EC4899" },
  { name: "Cannabis Crates", slug: "cannabis-crates", emoji: "💨", color: "#84CC16" },
  { name: "Hip-Hop Beats / Instrumentals", slug: "hip-hop-beats-instrumentals", emoji: "🔊", color: "#06B6D4" }
]

ActiveRecord::Base.transaction do
  categories.each_with_index do |attributes, index|
    category = Category.find_or_initialize_by(slug: attributes.fetch(:slug))
    action = category.new_record? ? "Created" : "Updated"

    category.assign_attributes(
      name: attributes.fetch(:name),
      emoji: attributes.fetch(:emoji),
      color: attributes.fetch(:color),
      family_color: attributes.fetch(:color),
      family_emoji: attributes.fetch(:emoji),
      is_main_family: true,
      position: index + 1,
      display_order: index + 1,
      parent: nil
    )
    category.save!

    puts "✓ #{action}: #{category.name}"
  end
end

puts "Restored #{categories.length} main categories."
