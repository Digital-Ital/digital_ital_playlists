class VisitSession < ApplicationRecord
  has_many :page_views, dependent: :destroy
  
  scope :human, -> { where(is_bot: false) }
  scope :bots, -> { where(is_bot: true) }
  scope :recent, -> { order(started_at: :desc) }
  scope :today, -> { where('started_at >= ?', Time.current.beginning_of_day) }
  scope :this_week, -> { where('started_at >= ?', 1.week.ago) }
  
  before_create :detect_bot
  
  def duration
    return 0 unless started_at && ended_at
    (ended_at - started_at).to_i
  end
  
  def duration_formatted
    seconds = duration
    return "#{seconds}s" if seconds < 60
    minutes = seconds / 60
    return "#{minutes}m" if minutes < 60
    hours = minutes / 60
    "#{hours}h #{minutes % 60}m"
  end
  
  private
  
  def detect_bot
    return unless user_agent.present?
    
    bot_patterns = [
      /bot/i, /crawl/i, /spider/i, /slurp/i,
      /googlebot/i, /bingbot/i, /yandex/i,
      /facebookexternalhit/i, /twitterbot/i,
      /whatsapp/i, /telegram/i, /slack/i,
      /linkedin/i, /pinterest/i,
      /headless/i, /phantom/i, /selenium/i
    ]
    
    self.is_bot = bot_patterns.any? { |pattern| user_agent.match?(pattern) }
  end
end
