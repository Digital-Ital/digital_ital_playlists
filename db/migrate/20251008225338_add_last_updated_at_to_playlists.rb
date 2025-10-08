class AddLastUpdatedAtToPlaylists < ActiveRecord::Migration[8.0]
  def change
    add_column :playlists, :last_updated_at, :datetime
  end
end
