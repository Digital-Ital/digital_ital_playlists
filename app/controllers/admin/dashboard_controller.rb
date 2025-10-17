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

    # Batch update info
    @latest_batch = BatchUpdate.order(created_at: :desc).first

    # Scheduler status
    @scheduler_paused = SchedulerSetting.paused?
    @quick_updates_enabled = SchedulerSetting.quick_updates?
    @next_update_time = calculate_next_update_time

    # Analytics stats
    begin
      @total_visits = VisitSession.count || 0
      @human_visits = VisitSession.human.count || 0
      @visits_today = VisitSession.where("started_at >= ?", Time.current.beginning_of_day).count || 0
      @visits_this_week = VisitSession.where("started_at >= ?", 1.week.ago).count || 0
      @total_reactions = Playlist.sum(:reaction_count) || 0
      @total_shares = ShareEvent.count || 0
      @shares_today = ShareEvent.where("created_at >= ?", Time.current.beginning_of_day).count || 0
      @total_spotify_opens = SpotifyOpen.count || 0
      @spotify_opens_today = SpotifyOpen.where("created_at >= ?", Time.current.beginning_of_day).count || 0
    rescue => e
      Rails.logger.error "Dashboard Analytics Error: #{e.message}"
      @total_visits = @human_visits = @visits_today = @visits_this_week = 0
      @total_reactions = @total_shares = @shares_today = 0
      @total_spotify_opens = @spotify_opens_today = 0
    end
  end

  private

  def calculate_next_update_time
    return nil if @scheduler_paused

    now = Time.current

    if @quick_updates_enabled
      # Quick updates run every 15 minutes
      # Find the next 15-minute mark
      minutes = now.min
      next_minutes = ((minutes / 15) + 1) * 15

      if next_minutes >= 60
        now.beginning_of_hour + 1.hour
      else
        now.beginning_of_hour + next_minutes.minutes
      end
    else
      # Normal updates run every hour at :40
      current_hour = now.hour
      current_minute = now.min

      if current_minute < 40
        # Next update is today at :40
        now.beginning_of_hour + 40.minutes
      else
        # Next update is tomorrow at :40
        now.beginning_of_hour + 1.hour + 40.minutes
      end
    end
  end
end
