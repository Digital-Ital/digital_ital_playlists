class CreatePlaylistUpdates < ActiveRecord::Migration[8.0]
  def change
    create_table :playlist_updates do |t|
      t.references :update_session, null: false, foreign_key: true
      t.references :playlist, null: false, foreign_key: true
      t.string :field_name
      t.string :old_value
      t.string :new_value
      t.string :status

      t.timestamps
    end
  end
end
