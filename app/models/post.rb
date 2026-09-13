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
  validate :slug_is_unused_in_every_locale

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
  # Mobility's `.i18n` scope rewrites the condition into a lookup of one
  # locale's key inside the column, so two posts may share a slug as long as
  # they don't share it *in the same locale*.
  #
  # Every locale is checked, not just `Mobility.locale`: the admin form writes
  # all of them in a single request that runs under one ambient locale, so
  # checking only that one lets the rest through to the per-locale unique
  # indexes, where the collision surfaces as a raw Postgres error instead of a
  # form error.
  def slug_is_unused_in_every_locale
    Mobility.available_locales.each do |locale|
      accessor = Mobility.normalize_locale_accessor(:slug, locale)

      # The literal value for this locale. The plain `slug` reader falls back
      # to English, which would ask whether the *English* slug is taken as,
      # say, a German one -- and reject a post over a German slug it does not
      # have.
      value = public_send(accessor)
      next if value.blank?

      # `.i18n` reads the locale off `Mobility.locale` when `where` runs rather
      # than from an argument, so the query is built inside the locale it asks
      # about.
      taken = Mobility.with_locale(locale) do
        scope = Post.i18n.where(slug: value).where(content_type: content_type)
        scope = scope.where.not(id: id) if persisted?
        scope.exists?
      end

      # Reported against `slug_de` rather than `slug`, so the admin form marks
      # the offending locale's tab instead of an ambient field nobody edits.
      errors.add(accessor, :taken) if taken
    end
  end
end
