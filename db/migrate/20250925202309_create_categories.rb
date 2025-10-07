class CreateCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :categories, if_not_exists: true do |t|
      t.string :name
      t.string :slug
      t.text :description
      t.string :color

      t.timestamps
    end
  end
end
