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
    
    # Special case: "Reggae Francais" has no volume number
    if vol_match.nil? && playlist.title.match?(/reggae\s*francais/i)
      return "Reggae Francais"
    end
    
    vol_num = vol_match ? vol_match[1].to_i : nil
    
    # Map volume numbers to specific category names as provided
    volume_to_category = {
      1 => "Dancehall",
      2 => "Raw Dubwise",
      3 => "Upbeat Roots Revival",
      4 => "Smooth Roots Revival",
      5 => "Pop / Soulful Reggae",
      6 => "Lounge Dubwise",
      7 => "Rock / Punk Reggae"
    }
    
    category_name = vol_num ? volume_to_category[vol_num] : "Reggae"
    
    "Vol#{vol_num} - #{category_name}"
  end
  
  helper_method :playlist_short_format
end

