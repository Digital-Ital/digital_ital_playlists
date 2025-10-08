class CreateUpdateLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :update_logs do |t|
      t.references :playlist, null: false, foreign_key: true
      t.string :log_type
      t.string :field_name
      t.text :old_value
      t.text :new_value
      t.references :track, null: false, foreign_key: true
      t.text :change_summary

      t.timestamps
    end
  end
end
