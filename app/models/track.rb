class Track < ApplicationRecord
  has_many :playlist_tracks, dependent: :destroy
  has_many :playlists, through: :playlist_tracks
  has_many :update_logs, dependent: :destroy

  validates :spotify_id, presence: true, uniqueness: true
  validates :name, presence: true
  validates :artist, presence: true

  scope :recent, -> { order(created_at: :desc) }

  def display_name
    "#{name} - #{artist}"
  end
end
