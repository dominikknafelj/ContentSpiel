class Post < ApplicationRecord
  has_rich_text :body

  enum :content_type, { blog: 0, resume_entry: 1, now_update: 2 }

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: { scope: :content_type }

  before_validation :generate_slug_from_title, on: :create

  private

  def generate_slug_from_title
    self.slug = title.to_s.parameterize if slug.blank? && title.present?
  end
end
