class Post < ApplicationRecord
  has_rich_text :body

  has_many :post_tags, dependent: :destroy
  has_many :tags, through: :post_tags

  has_many :post_relations, dependent: :destroy
  has_many :related_posts, through: :post_relations

  enum :content_type, { blog: 0, resume_entry: 1, now_update: 2 }

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: { scope: :content_type }

  before_validation :generate_slug_from_title, on: :create

  def all_related_posts
    forward_ids = PostRelation.where(post_id: id).select(:related_post_id)
    backward_ids = PostRelation.where(related_post_id: id).select(:post_id)
    Post.where(id: forward_ids).or(Post.where(id: backward_ids))
  end

  private

  def generate_slug_from_title
    self.slug = title.to_s.parameterize if slug.blank? && title.present?
  end
end
