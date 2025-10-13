class Playlist < ApplicationRecord
  has_and_belongs_to_many :categories, join_table: :playlist_categories
  has_many :playlist_updates, dependent: :destroy
  has_many :playlist_tracks, dependent: :destroy
  has_many :tracks, through: :playlist_tracks
  has_many :update_logs, dependent: :destroy
  has_many :share_events, dependent: :destroy

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
  scope :stale, -> { where("last_updated_at IS NULL OR last_updated_at < ?", 1.week.ago) }
  scope :recently_updated, -> { where("last_updated_at >= ?", 1.week.ago).order(last_updated_at: :desc) }

  def duration_formatted
    return duration if duration.present?
    "#{track_count} tracks"
  end

  def spotify_id
    return nil unless spotify_url.present?
    spotify_url.match(/playlist\/([a-zA-Z0-9]+)/)&.[](1)
  end

  def needs_update?
    last_updated_at.nil? || last_updated_at < 1.day.ago
  end

  def last_updated_humanized
    return "Never" if last_updated_at.nil?
    time_ago_in_words(last_updated_at) + " ago"
  end
end
