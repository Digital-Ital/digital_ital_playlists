class Category < ApplicationRecord
  has_and_belongs_to_many :playlists, join_table: :playlist_categories
  belongs_to :parent, class_name: "Category", optional: true
  has_many :children, class_name: "Category", foreign_key: "parent_id", dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  validates :position, uniqueness: { scope: :parent_id }, allow_nil: true

  before_validation :generate_slug, on: [:create, :update]
  before_destroy :check_for_children

  scope :ordered, -> {
    order(Arel.sql("display_order NULLS LAST, position NULLS LAST, name ASC"))
  }

  scope :roots, -> { where(parent_id: nil).ordered }
  
  scope :main_families, -> { where(is_main_family: true).ordered }

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

  def check_for_children
    if children.exists?
      errors.add(:base, "Cannot delete category with subcategories. Please delete or move subcategories first.")
      throw(:abort)
    end
  end
end
