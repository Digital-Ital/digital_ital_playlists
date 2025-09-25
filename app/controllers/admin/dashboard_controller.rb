class Admin::DashboardController < Admin::BaseController
  def index
    @categories_count = Category.count
    @playlists_count = Playlist.count
    @uncategorized_count = Playlist.where(category_id: nil).count
  end
end

class Admin::DashboardController < Admin::BaseController
  def index
    @categories_count = Category.count
    @playlists_count = Playlist.count
    @uncategorized_count = Playlist.where(category_id: nil).count
  end
end
