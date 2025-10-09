class BatchUpdate < ApplicationRecord
  validates :status, inclusion: { in: %w[idle running completed failed] }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: 'running') }
  
  def progress_percentage
    return 0 if total_count.zero?
    ((current_index.to_f / total_count) * 100).round
  end
end
