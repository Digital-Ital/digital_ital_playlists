class PlaylistUpdate < ApplicationRecord
  belongs_to :update_session
  belongs_to :playlist
  
  validates :field_name, presence: true
  validates :status, inclusion: { in: %w[pending confirmed rejected applied] }
  
  scope :by_field, ->(field) { where(field_name: field) }
  scope :pending, -> { where(status: 'pending') }
  scope :confirmed, -> { where(status: 'confirmed') }
  
  def changed?
    old_value != new_value
  end
  
  def display_change
    case field_name
    when 'track_count'
      "#{old_value} → #{new_value} tracks"
    when 'title'
      "\"#{old_value}\" → \"#{new_value}\""
    when 'duration'
      "#{old_value} → #{new_value}"
    else
      "#{old_value} → #{new_value}"
    end
  end
end
