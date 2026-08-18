class PlaylistCategory < ApplicationRecord
  belongs_to :playlist
  belongs_to :category
end
