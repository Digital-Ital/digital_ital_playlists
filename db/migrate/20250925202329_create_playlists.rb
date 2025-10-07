class CreatePlaylists < ActiveRecord::Migration[8.0]
  def change
    create_table :playlists, if_not_exists: true do |t|
      t.string :title
      t.text :description
      t.string :cover_image_url
      t.string :spotify_url
      t.integer :track_count
      t.string :duration
      t.references :category, null: true
      t.boolean :featured
      t.integer :position

      t.timestamps
    end
    
    # Add foreign key separately to avoid issues if categories table doesn't exist yet
    add_foreign_key :playlists, :categories, if_not_exists: true
  end
end
