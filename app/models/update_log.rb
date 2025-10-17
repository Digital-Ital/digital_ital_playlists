class UpdateLog < ApplicationRecord
  belongs_to :playlist
  belongs_to :track, optional: true  # Only present for track-related changes

  validates :log_type, presence: true, inclusion: { in: %w[playlist_metadata track_added track_removed] }
  validates :change_summary, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :by_playlist, ->(playlist_id) { where(playlist_id: playlist_id) }
  scope :by_type, ->(type) { where(log_type: type) }
  scope :track_changes, -> { where(log_type: %w[track_added track_removed]) }
  scope :metadata_changes, -> { where(log_type: "playlist_metadata") }

  def display_summary
    case log_type
    when "track_added"
      "Added: #{track&.display_name || 'Unknown Track'}"
    when "track_removed"
      "Removed: #{track&.display_name || change_summary}"
    when "playlist_metadata"
      "#{field_name&.humanize}: #{old_value} → #{new_value}"
    else
      change_summary
    end
  end
end
