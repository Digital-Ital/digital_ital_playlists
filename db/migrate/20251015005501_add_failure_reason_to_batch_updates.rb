class AddFailureReasonToBatchUpdates < ActiveRecord::Migration[8.0]
  def change
    add_column :batch_updates, :failure_reason, :text
  end
end
