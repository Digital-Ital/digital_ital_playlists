class SetupDatabase < ActiveRecord::Migration[8.0]
  def up
    # Create categories table if it doesn't exist
    unless table_exists?(:categories)
      create_table :categories do |t|
        t.string :name
        t.string :slug
        t.text :description
        t.string :color
        t.integer :position
        t.references :parent, null: true, foreign_key: { to_table: :categories }

        t.timestamps
      end
    end

    # Create playlists table if it doesn't exist
    unless table_exists?(:playlists)
      create_table :playlists do |t|
        t.string :title
        t.text :description
        t.string :cover_image_url
        t.string :spotify_url
        t.integer :track_count
        t.string :duration
        t.references :category, null: true, foreign_key: true
        t.boolean :featured
        t.integer :position

        t.timestamps
      end
    end

    # Add parent_id to categories if it doesn't exist
    unless column_exists?(:categories, :parent_id)
      add_reference :categories, :parent, null: true, foreign_key: { to_table: :categories }
    end

    # Add position to categories if it doesn't exist
    unless column_exists?(:categories, :position)
      add_column :categories, :position, :integer
    end

    # Make category_id nullable if it's not already
    if column_exists?(:playlists, :category_id)
      change_column_null :playlists, :category_id, true
    end
  end

  def down
    # This migration is designed to be safe and idempotent
    # No down migration needed as it only creates what's missing
  end
end