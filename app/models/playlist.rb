class Playlist < ApplicationRecord
  has_and_belongs_to_many :categories, join_table: :playlist_categories
  has_many :playlist_updates, dependent: :destroy

  validates :title, presence: true
  validates :spotify_url, presence: true, uniqueness: true, format: { with: URI.regexp(%w[http https]) }
  validates :track_count, presence: true, numericality: { greater_than: 0 }

  scope :featured, -> { where(featured: true) }
  scope :ordered, -> { order(:position, :title) }
  scope :by_category, ->(category) { joins(:categories).where(categories: { id: category.id }) }
  # Return playlists that belong to ANY of the given category_ids (OR semantics)
  scope :by_category_ids, ->(category_ids) do
    if category_ids.present?
      joins(:categories)
        .where(playlist_categories: { category_id: category_ids })
        .distinct
    end
  end

  def duration_formatted
    return duration if duration.present?
    "#{track_count} tracks"
  end

  def spotify_id
    return nil unless spotify_url.present?
    spotify_url.match(/playlist\/([a-zA-Z0-9]+)/)&.[](1)
  end
end
