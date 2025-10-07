class AddDisplayFieldsToCategories < ActiveRecord::Migration[8.0]
  def change
    add_column :categories, :emoji, :string
    add_column :categories, :display_order, :integer
    add_column :categories, :is_main_family, :boolean
    add_column :categories, :family_color, :string
    add_column :categories, :family_emoji, :string
  end
end
