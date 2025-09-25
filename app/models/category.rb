class Category < ApplicationRecord
  has_many :playlists, dependent: :destroy
  belongs_to :parent, class_name: 'Category', optional: true
  has_many :children, class_name: 'Category', foreign_key: 'parent_id', dependent: :nullify
  
  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  
  before_validation :generate_slug, on: :create
  
  scope :ordered, -> { order(:position, :name) }

  scope :roots, -> { where(parent_id: nil).ordered }

  def descendant_ids
    ids = []
    children.each do |child|
      ids << child.id
      ids.concat(child.descendant_ids)
    end
    ids
  end

  def self.tree
    roots.includes(children: :children)
  end
  
  private
  
  def generate_slug
    self.slug = name.parameterize if name.present?
  end
end
