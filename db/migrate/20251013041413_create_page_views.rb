class CreatePageViews < ActiveRecord::Migration[8.0]
  def change
    create_table :page_views do |t|
      t.references :visit_session, null: false, foreign_key: true
      t.string :url
      t.string :page_type
      t.integer :category_id
      t.integer :playlist_id
      t.string :search_query
      t.string :action_type
      t.integer :time_on_page, default: 0

      t.timestamps
    end
    
    add_index :page_views, :created_at
    add_index :page_views, :page_type
    add_index :page_views, :category_id
    add_index :page_views, :playlist_id
    add_index :page_views, :search_query
  end
end
