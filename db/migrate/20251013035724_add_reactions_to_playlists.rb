class AddReactionsToPlaylists < ActiveRecord::Migration[8.0]
  def change
    add_column :playlists, :reaction_count, :integer, default: 0, null: false
  end
end
