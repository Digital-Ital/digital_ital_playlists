class Admin::DashboardController < Admin::BaseController
  def index
    @categories_count = Category.count
    @playlists_count = Playlist.count
    @uncategorized_count = Playlist.left_joins(:categories).where(categories: { id: nil }).count
    @featured_count = Playlist.where(featured: true).count
    @root_categories = Category.where(parent_id: nil).count
    @subcategories = Category.where.not(parent_id: nil).count
  end
end
