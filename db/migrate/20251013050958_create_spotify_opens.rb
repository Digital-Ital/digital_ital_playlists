class CreateSpotifyOpens < ActiveRecord::Migration[7.1]
  def change
    create_table :spotify_opens do |t|
      t.references :playlist, null: false, foreign_key: true
      t.string :location # 'featured', 'regular', 'category', 'search', 'whats_new'
      t.string :session_id
      t.string :user_agent
      t.string :referrer
      t.string :ip_address

      t.timestamps
    end

    add_index :spotify_opens, :created_at
    add_index :spotify_opens, :location
    add_index :spotify_opens, :session_id
  end
end
