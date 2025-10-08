class CreateTracks < ActiveRecord::Migration[8.0]
  def change
    create_table :tracks do |t|
      t.string :spotify_id
      t.string :name
      t.string :artist
      t.string :album
      t.string :image_url
      t.integer :duration_ms
      t.string :preview_url
      t.string :external_url

      t.timestamps
    end
    add_index :tracks, :spotify_id, unique: true
  end
end
