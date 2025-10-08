class CreateUpdateSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :update_sessions do |t|
      t.datetime :started_at
      t.datetime :completed_at
      t.string :status
      t.integer :total_playlists
      t.integer :updated_playlists

      t.timestamps
    end
  end
end
