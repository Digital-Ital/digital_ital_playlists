class AddPlatformLinksToPlaylists < ActiveRecord::Migration[7.1]
  def change
    add_column :playlists, :youtube_url, :string
    add_column :playlists, :tidal_url, :string
    add_column :playlists, :qobuz_url, :string
    add_column :playlists, :deezer_url, :string
    add_column :playlists, :soundcloud_url, :string
    add_column :playlists, :mixcloud_url, :string
  end
end
