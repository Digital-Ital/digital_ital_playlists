class CreateVisitSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :visit_sessions do |t|
      t.string :session_id, null: false
      t.string :ip_address
      t.string :user_agent
      t.string :referrer
      t.boolean :is_bot, default: false
      t.string :first_page
      t.string :last_page
      t.integer :page_views_count, default: 0
      t.datetime :started_at
      t.datetime :ended_at

      t.timestamps
    end

    add_index :visit_sessions, :session_id, unique: true
    add_index :visit_sessions, :started_at
    add_index :visit_sessions, :is_bot
    add_index :visit_sessions, :ip_address
  end
end
