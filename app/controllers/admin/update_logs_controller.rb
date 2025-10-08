class Admin::UpdateLogsController < Admin::BaseController
  def index
    @update_logs = UpdateLog.includes(:playlist, :track)
                             .recent
                             .page(params[:page])
                             .per(50)
    
    # Group by type if requested
    if params[:type].present?
      @update_logs = @update_logs.by_type(params[:type])
    end
    
    # Filter by playlist if requested
    if params[:playlist_id].present?
      @update_logs = @update_logs.by_playlist(params[:playlist_id])
    end
  end
end

