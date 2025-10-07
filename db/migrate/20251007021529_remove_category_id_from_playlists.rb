class RemoveCategoryIdFromPlaylists < ActiveRecord::Migration[8.0]
  def change
    remove_foreign_key :playlists, :categories if foreign_key_exists?(:playlists, :categories)
    remove_reference :playlists, :category_id, null: false, foreign_key: false
  end
end
