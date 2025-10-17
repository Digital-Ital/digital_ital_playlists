class Admin::BatchUpdatesController < Admin::BaseController
  def index
    begin
      @batch_updates = BatchUpdate.order(created_at: :desc).limit(20)

      # Get summary stats with safe defaults
      @total_batches = BatchUpdate.count || 0
      @successful_batches = BatchUpdate.where(status: "completed").count || 0
      @failed_batches = BatchUpdate.where(status: "failed").count || 0
      @running_batches = BatchUpdate.where(status: "running").count || 0
      @total_changes = BatchUpdate.sum(:changes_count) || 0
      @last_24h_changes = BatchUpdate.where("created_at >= ?", 24.hours.ago).sum(:changes_count) || 0
    rescue => e
      Rails.logger.error "Batch Updates Index Error: #{e.message}"
      @batch_updates = []
      @total_batches = @successful_batches = @failed_batches = @running_batches = 0
      @total_changes = @last_24h_changes = 0
    end
  end

  def show
    begin
      @batch_update = BatchUpdate.find(params[:id])

      # Get detailed information about this batch
      @playlists_updated = @batch_update.changes_count || 0
      @duration = if @batch_update.completed_at && @batch_update.started_at
                    (@batch_update.completed_at - @batch_update.started_at).round(2)
      else
                    nil
      end
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_batch_updates_path, alert: "Batch update not found"
    rescue => e
      Rails.logger.error "Batch Update Show Error: #{e.message}"
      redirect_to admin_batch_updates_path, alert: "Error loading batch update details"
    end
  end
end
