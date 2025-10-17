class SpotifyOpen < ApplicationRecord
  belongs_to :playlist

  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }
  scope :this_week, -> { where("created_at >= ?", 1.week.ago) }
  scope :by_location, ->(location) { where(location: location) }
end
