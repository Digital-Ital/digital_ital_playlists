class UpdateSession < ApplicationRecord
  has_many :playlist_updates, dependent: :destroy
end
