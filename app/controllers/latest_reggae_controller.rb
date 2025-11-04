class LatestReggaeController < ApplicationController
  def index
    playlists = Playlist.featured.includes(:categories, :tracks).limit(10)
    
    # Sort by volume number extracted from title
    @featured_playlists = playlists.sort_by do |playlist|
      # Extract volume number from title (e.g., "Vol 7", "Vol7", "Volume 7")
      vol_match = playlist.title.match(/vol\s*(\d+)/i)
      vol_match ? vol_match[1].to_i : 999
    end
  end
  
  # Helper method to extract volume number and category for display
  def playlist_short_format(playlist)
    vol_match = playlist.title.match(/vol\s*(\d+)/i)
    vol_num = vol_match ? vol_match[1] : "?"
    
    # Get primary category name
    category_name = playlist.categories.first&.name || "Reggae"
    
    "Vol#{vol_num} is #{category_name}"
  end
  
  helper_method :playlist_short_format
end

