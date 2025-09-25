class Category < ApplicationRecord
  has_many :playlists, dependent: :destroy
  
  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  
  before_validation :generate_slug, on: :create
  
  scope :ordered, -> { order(:position, :name) }
  
  private
  
  def generate_slug
    self.slug = name.parameterize if name.present?
  end
end
