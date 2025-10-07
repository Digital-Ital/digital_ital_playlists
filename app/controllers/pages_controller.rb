class PagesController < ApplicationController
  def home
    @categories = Category.roots.includes(children: :children)
    @main_families = Category.main_families.includes(children: :children)
  end
end
