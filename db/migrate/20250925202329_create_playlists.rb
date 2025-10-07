class CreatePlaylists < ActiveRecord::Migration[8.0]
  def change
    create_table :playlists, if_not_exists: true do |t|
      t.string :title
      t.text :description
      t.string :cover_image_url
      t.string :spotify_url
      t.integer :track_count
      t.string :duration
      t.references :category, null: false, foreign_key: true
      t.boolean :featured
      t.integer :position

      t.timestamps
    end
  end
end
