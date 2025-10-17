class CreateSchedulerSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :scheduler_settings do |t|
      t.string :name
      t.string :value

      t.timestamps
    end
  end
end
