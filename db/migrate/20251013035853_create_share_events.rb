class CreateShareEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :share_events do |t|
      t.references :playlist, null: false, foreign_key: true
      t.string :platform
      t.text :shared_content
      t.string :user_agent
      t.string :referrer
      t.string :ip_address

      t.timestamps
    end

    add_index :share_events, :created_at
    add_index :share_events, :platform
  end
end
