class UpdateSession < ApplicationRecord
  has_many :playlist_updates, dependent: :destroy
  
  validates :status, inclusion: { in: %w[running completed failed] }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: 'completed') }
  
  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end
  
  def success_rate
    return 0 if total_playlists.zero?
    (updated_playlists.to_f / total_playlists * 100).round(1)
  end
end
