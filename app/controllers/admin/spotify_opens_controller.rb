class Admin::SpotifyOpensController < Admin::BaseController
  def index
    @spotify_opens = SpotifyOpen.includes(:playlist)
                                 .order(created_at: :desc)
                                 .page(params[:page])
                                 .per(50)
    
    # Stats for dashboard
    @total_opens = SpotifyOpen.count
    @opens_today = SpotifyOpen.where('created_at >= ?', Time.current.beginning_of_day).count
    @opens_this_week = SpotifyOpen.where('created_at >= ?', 1.week.ago).count
    @opens_by_location = SpotifyOpen.group(:location).count
    @most_opened_playlists = Playlist.joins(:spotify_opens)
                                      .select('playlists.*, COUNT(spotify_opens.id) as opens_count')
                                      .group('playlists.id')
                                      .order('opens_count DESC')
                                      .limit(10)
  end
end

