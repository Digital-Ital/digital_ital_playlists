class MakePlaylistCategoryOptional < ActiveRecord::Migration[8.0]
  def change
    change_column_null :playlists, :category_id, true
  end
end
