class CreateBatchUpdates < ActiveRecord::Migration[8.0]
  def change
    create_table :batch_updates do |t|
      t.string :status
      t.integer :current_index
      t.integer :total_count
      t.string :current_playlist_title
      t.integer :changes_count
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end
