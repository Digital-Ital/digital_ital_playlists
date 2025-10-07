class RemoveCategoryIdFromPlaylists < ActiveRecord::Migration[8.0]
  def change
    remove_foreign_key :playlists, :categories if foreign_key_exists?(:playlists, :categories)
    remove_column :playlists, :category_id if column_exists?(:playlists, :category_id)
  end
end
