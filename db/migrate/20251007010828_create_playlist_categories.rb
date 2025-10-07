class CreatePlaylistCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :playlist_categories, if_not_exists: true do |t|
      t.references :playlist, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true

      t.timestamps
    end

    add_index :playlist_categories, [:playlist_id, :category_id], unique: true, if_not_exists: true
  end
end
