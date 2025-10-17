class PageView < ApplicationRecord
  belongs_to :visit_session
  belongs_to :category, optional: true
  belongs_to :playlist, optional: true

  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(page_type: type) }
  scope :with_search, -> { where.not(search_query: nil) }

  # Page types: home, category, playlist, whats_new, search
end
