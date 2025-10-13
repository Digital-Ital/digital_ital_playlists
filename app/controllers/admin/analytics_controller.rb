class Admin::AnalyticsController < ApplicationController
  def index
    # Time periods
    @today = Time.current.beginning_of_day
    @week_ago = 1.week.ago
    @month_ago = 1.month.ago
    
    # Overall stats
    @total_visits = VisitSession.count
    @total_page_views = PageView.count
    @human_visits = VisitSession.human.count
    @bot_visits = VisitSession.bots.count
    
    # Today's stats
    @visits_today = VisitSession.where('started_at >= ?', @today).count
    @human_visits_today = VisitSession.human.where('started_at >= ?', @today).count
    @page_views_today = PageView.where('created_at >= ?', @today).count
    
    # This week
    @visits_this_week = VisitSession.where('started_at >= ?', @week_ago).count
    @human_visits_this_week = VisitSession.human.where('started_at >= ?', @week_ago).count
    
    # Traffic sources (top referrers)
    @top_referrers = VisitSession.human
                                 .where.not(referrer: [nil, ''])
                                 .group(:referrer)
                                 .count
                                 .sort_by { |_, count| -count }
                                 .first(10)
    
    # Most viewed categories
    @top_categories = PageView.where.not(category_id: nil)
                              .joins("LEFT JOIN categories ON categories.id = page_views.category_id")
                              .group('categories.id, categories.name')
                              .select('categories.name, COUNT(page_views.id) as view_count')
                              .order('view_count DESC')
                              .limit(10)
    
    # Most viewed playlists (clicked to open)
    @top_playlists = PageView.where.not(playlist_id: nil)
                             .joins("LEFT JOIN playlists ON playlists.id = page_views.playlist_id")
                             .group('playlists.id, playlists.title')
                             .select('playlists.title, COUNT(page_views.id) as view_count')
                             .order('view_count DESC')
                             .limit(10)
    
    # Popular search queries
    @top_searches = PageView.with_search
                            .where('created_at >= ?', @week_ago)
                            .group(:search_query)
                            .count
                            .sort_by { |_, count| -count }
                            .first(10)
    
    # Recent human sessions
    @recent_sessions = VisitSession.human
                                   .recent
                                   .limit(20)
    
    # Bot breakdown
    @bot_types = VisitSession.bots
                             .where('started_at >= ?', @week_ago)
                             .group(:user_agent)
                             .count
                             .sort_by { |_, count| -count }
                             .first(10)
    
    # Average session duration (human only)
    human_sessions_with_end = VisitSession.human
                                          .where.not(ended_at: nil)
                                          .where('started_at >= ?', @week_ago)
    
    if human_sessions_with_end.any?
      total_duration = human_sessions_with_end.sum { |s| s.duration }
      @avg_session_duration = (total_duration / human_sessions_with_end.count).to_i
    else
      @avg_session_duration = 0
    end
    
    # Page views by hour (last 24h) for live traffic visualization
    @hourly_views = PageView.where('created_at >= ?', 24.hours.ago)
                            .group("strftime('%H', created_at)")
                            .count
  end
end

