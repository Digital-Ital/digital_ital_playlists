class AddSourceToBatchUpdates < ActiveRecord::Migration[8.0]
  def change
    add_column :batch_updates, :source, :string
  end
end
