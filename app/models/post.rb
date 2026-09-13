class Post < ApplicationRecord
  extend Mobility

  # `title`, `slug` and `excerpt` are jsonb columns holding one value per
  # locale; reading or writing them goes through the current Mobility.locale.
  translates :title, :slug, :excerpt

  # Rich text can't live in a jsonb column -- it has attachments and its own
  # table -- so `body` uses mobility-actiontext, which keeps one
  # ActionText::RichText row per locale. This replaces `has_rich_text :body`.
  translates :body, backend: :action_text

  has_many :post_tags, dependent: :destroy
  has_many :tags, through: :post_tags

  has_many :post_relations, dependent: :destroy
  has_many :related_posts, through: :post_relations

  # PostRelation holds two FKs into posts. `post_relations` only covers the
  # `post_id` side; without this the `related_post_id` side is left dangling
  # and destroying the post raises ActiveRecord::InvalidForeignKey.
  has_many :inverse_post_relations, class_name: "PostRelation",
    foreign_key: :related_post_id, dependent: :destroy, inverse_of: :related_post

  enum :content_type, { blog: 0, resume_entry: 1, now_update: 2 }

  validates :title, presence: true
  validates :slug, presence: true
  validate :slug_is_unused_in_this_locale

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

  # `validates :slug, uniqueness:` would emit `WHERE posts.slug = 'hello'`,
  # comparing a jsonb column to a string -- which Postgres rejects outright.
  # Mobility's `.i18n` scope rewrites the condition into a lookup of the
  # current locale's key inside the column, so two posts may share a slug as
  # long as they don't share it *in the same locale*.
  def slug_is_unused_in_this_locale
    return if slug.blank?

    taken = Post.i18n.where(slug: slug).where(content_type: content_type)
    taken = taken.where.not(id: id) if persisted?

    errors.add(:slug, :taken) if taken.exists?
  end
end
