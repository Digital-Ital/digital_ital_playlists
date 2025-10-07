namespace :db do
  desc "Setup database tables safely"
  task setup_safe: :environment do
    puts "Setting up database safely..."
    
    # Create categories table if it doesn't exist
    unless ActiveRecord::Base.connection.table_exists?(:categories)
      puts "Creating categories table..."
      ActiveRecord::Base.connection.create_table :categories do |t|
        t.string :name
        t.string :slug
        t.text :description
        t.string :color
        t.integer :position
        t.references :parent, null: true, foreign_key: { to_table: :categories }

        t.timestamps
      end
    else
      puts "Categories table already exists"
    end

    # Create playlists table if it doesn't exist
    unless ActiveRecord::Base.connection.table_exists?(:playlists)
      puts "Creating playlists table..."
      ActiveRecord::Base.connection.create_table :playlists do |t|
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
    else
      puts "Playlists table already exists"
    end

    # Add parent_id to categories if it doesn't exist
    unless ActiveRecord::Base.connection.column_exists?(:categories, :parent_id)
      puts "Adding parent_id to categories..."
      ActiveRecord::Base.connection.add_reference :categories, :parent, null: true, foreign_key: { to_table: :categories }
    end

    # Add position to categories if it doesn't exist
    unless ActiveRecord::Base.connection.column_exists?(:categories, :position)
      puts "Adding position to categories..."
      ActiveRecord::Base.connection.add_column :categories, :position, :integer
    end

    # Add missing columns to playlists table if they don't exist
    unless ActiveRecord::Base.connection.column_exists?(:playlists, :category_id)
      puts "Adding category_id to playlists..."
      ActiveRecord::Base.connection.add_reference :playlists, :category, null: true, foreign_key: true
    end

    unless ActiveRecord::Base.connection.column_exists?(:playlists, :featured)
      puts "Adding featured to playlists..."
      ActiveRecord::Base.connection.add_column :playlists, :featured, :boolean
    end

    unless ActiveRecord::Base.connection.column_exists?(:playlists, :position)
      puts "Adding position to playlists..."
      ActiveRecord::Base.connection.add_column :playlists, :position, :integer
    end

    unless ActiveRecord::Base.connection.column_exists?(:playlists, :track_count)
      puts "Adding track_count to playlists..."
      ActiveRecord::Base.connection.add_column :playlists, :track_count, :integer
    end

    unless ActiveRecord::Base.connection.column_exists?(:playlists, :duration)
      puts "Adding duration to playlists..."
      ActiveRecord::Base.connection.add_column :playlists, :duration, :string
    end

    unless ActiveRecord::Base.connection.column_exists?(:playlists, :cover_image_url)
      puts "Adding cover_image_url to playlists..."
      ActiveRecord::Base.connection.add_column :playlists, :cover_image_url, :string
    end

    unless ActiveRecord::Base.connection.column_exists?(:playlists, :spotify_url)
      puts "Adding spotify_url to playlists..."
      ActiveRecord::Base.connection.add_column :playlists, :spotify_url, :string
    end

    unless ActiveRecord::Base.connection.column_exists?(:playlists, :description)
      puts "Adding description to playlists..."
      ActiveRecord::Base.connection.add_column :playlists, :description, :text
    end

    # Make category_id nullable if it's not already
    if ActiveRecord::Base.connection.column_exists?(:playlists, :category_id)
      puts "Making category_id nullable..."
      ActiveRecord::Base.connection.change_column_null :playlists, :category_id, true
    end

    puts "Database setup complete!"
  end
end
