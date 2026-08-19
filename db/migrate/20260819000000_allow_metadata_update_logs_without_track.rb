class AllowMetadataUpdateLogsWithoutTrack < ActiveRecord::Migration[8.0]
  def change
    change_column_null :update_logs, :track_id, true
  end
end
