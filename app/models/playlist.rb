class Playlist < ApplicationRecord
  belongs_to :category, optional: true

  validates :title, presence: true
  validates :spotify_url, presence: true, format: { with: URI.regexp(%w[http https]) }
  validates :track_count, presence: true, numericality: { greater_than: 0 }

  scope :featured, -> { where(featured: true) }
  scope :ordered, -> { order(:position, :title) }
  scope :by_category, ->(category) { where(category: category) }

  def duration_formatted
    return duration if duration.present?
    "#{track_count} tracks"
  end

  def spotify_id
    return nil unless spotify_url.present?
    spotify_url.match(/playlist\/([a-zA-Z0-9]+)/)&.[](1)
  end
end
