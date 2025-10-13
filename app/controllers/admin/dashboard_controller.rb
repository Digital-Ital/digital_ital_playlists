class Admin::DashboardController < Admin::BaseController
  def index
    # Playlist & Category stats
    @categories_count = Category.count
    @playlists_count = Playlist.count
    @uncategorized_count = Playlist.left_joins(:categories).where(categories: { id: nil }).count
    @featured_count = Playlist.where(featured: true).count
    @root_categories = Category.where(parent_id: nil).count
    @subcategories = Category.where.not(parent_id: nil).count
    @recent_playlists = Playlist.includes(:categories).order(created_at: :desc).limit(5)
    
    # Analytics stats
    begin
      @total_visits = VisitSession.count || 0
      @human_visits = VisitSession.human.count || 0
      @visits_today = VisitSession.where('started_at >= ?', Time.current.beginning_of_day).count || 0
      @visits_this_week = VisitSession.where('started_at >= ?', 1.week.ago).count || 0
      @total_reactions = Playlist.sum(:reaction_count) || 0
      @total_shares = ShareEvent.count || 0
      @shares_today = ShareEvent.where('created_at >= ?', Time.current.beginning_of_day).count || 0
    rescue => e
      Rails.logger.error "Dashboard Analytics Error: #{e.message}"
      @total_visits = @human_visits = @visits_today = @visits_this_week = 0
      @total_reactions = @total_shares = @shares_today = 0
    end
  end
end
