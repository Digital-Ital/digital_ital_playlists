class Admin::BatchUpdatesController < Admin::BaseController
  def index
    @batch_updates = BatchUpdate.order(created_at: :desc).page(params[:page]).per(20)
    
    # Get summary stats
    @total_batches = BatchUpdate.count
    @successful_batches = BatchUpdate.where(status: 'completed').count
    @failed_batches = BatchUpdate.where(status: 'failed').count
    @running_batches = BatchUpdate.where(status: 'running').count
    @total_changes = BatchUpdate.sum(:changes_count) || 0
    @last_24h_changes = BatchUpdate.where('created_at >= ?', 24.hours.ago).sum(:changes_count) || 0
  end
  
  def show
    @batch_update = BatchUpdate.find(params[:id])
    
    # Get detailed information about this batch
    @playlists_updated = @batch_update.changes_count
    @duration = if @batch_update.completed_at && @batch_update.started_at
                  (@batch_update.completed_at - @batch_update.started_at).round(2)
                else
                  nil
                end
  end
end
