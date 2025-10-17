class Admin::ShareEventsController < Admin::BaseController
  def index
    @share_events = ShareEvent.includes(:playlist)
                               .order(created_at: :desc)
                               .page(params[:page])
                               .per(50)

    # Stats for dashboard
    @total_shares = ShareEvent.count
    @shares_today = ShareEvent.where("created_at >= ?", Time.current.beginning_of_day).count
    @shares_this_week = ShareEvent.where("created_at >= ?", 1.week.ago).count
    @shares_by_platform = ShareEvent.group(:platform).count
    @most_shared_playlists = Playlist.joins(:share_events)
                                      .select("playlists.*, COUNT(share_events.id) as shares_count")
                                      .group("playlists.id")
                                      .order("shares_count DESC")
                                      .limit(10)
  end
end
