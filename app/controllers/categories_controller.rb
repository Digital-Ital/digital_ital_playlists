class CategoriesController < ApplicationController
  def show
    @category = Category.find_by!(slug: params[:id])
    @main_families = Category.main_families.includes(children: :children)

    # For the tree view - we'll highlight this category
    @current_category_id = @category.id
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Category not found"
  end
end
