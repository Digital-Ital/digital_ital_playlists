class PlaylistTrack < ApplicationRecord
  belongs_to :playlist
  belongs_to :track

  validates :added_at, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent_additions, -> { order(added_at: :desc) }
  scope :by_playlist, ->(playlist_id) { where(playlist_id: playlist_id) }
  scope :added_since, ->(date) { where("added_at >= ?", date) }
end
