class Post < ApplicationRecord
  extend Mobility
  include LocalizedSlug
  include Publishable

  localized_slug scope: :content_type

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

  # Resume entries' structured fields (spec §10.3), kept in the existing
  # `metadata` jsonb so no migration is needed and other content types ignore
  # them. Dates stay ISO strings ("2023-01-01"); an empty end date means
  # "current role".
  ROLE_TYPES = {
    "ic" => "Individual contributor", "lead" => "Lead",
    "manager" => "Manager", "freelance" => "Freelance"
  }.freeze

  store_accessor :metadata, :company, :role, :start_date, :end_date, :role_type

  # "Titled" means *some* locale has a title, not "the locale that happens to
  # be ambient when this record is saved" -- a post may legitimately exist in
  # German before it is ever written in English, or vice versa (see the
  # pinned test "a title in a non-default locale satisfies the presence
  # requirement"). Before this task, `validates :title, presence: true` got
  # this right by accident: Mobility's own global fallback plugin meant the
  # plain reader returned *some* locale's title regardless of which one was
  # ambient. Now that plain readers read literally (config/initializers
  # /mobility.rb), the same `validates :title, presence: true` would instead
  # reject a fully-titled post just because it was saved inside a
  # `Mobility.with_locale(:de)` block for an unrelated German-only edit -- so
  # this reads the raw jsonb hash directly rather than through Mobility,
  # sidestepping the ambient locale entirely.
  validate :title_present_in_any_locale
  validates :slug, presence: true
  validates :role_type, inclusion: { in: ROLE_TYPES.keys }, allow_blank: true

  # The post whose slug in `locale` is `slug` -- as a visitor reading the site
  # in that locale sees it, meaning *through* Mobility's fallbacks, exactly the
  # way `Page` builds its cached paths (spec section 6). A post translated into
  # German but left with only its English slug is linked as ".../my-post" on
  # the German listing, so that is the URL its detail view has to answer to.
  #
  # Meant to be called on a scope that has already narrowed the candidates to
  # the ones a listing would show, e.g.
  # `Post.published.where(content_type: "blog").find_by_localized_slug(...)`.
  #
  # Two queries rather than one OR-ed condition so that the requested locale's
  # own slug always wins: otherwise a post reachable here only by fallback
  # could shadow the post whose localized URL this actually is. Each is an
  # equality test the per-locale unique indexes on
  # `(content_type, slug ->> '<locale>')` already cover.
  def self.find_by_localized_slug(locale, slug)
    return nil if slug.blank?

    exact = where("slug ->> ? = ?", locale.to_s, slug).first
    return exact if exact
    return nil if locale.to_s == I18n.default_locale.to_s

    # The fallback half, and why it tests for NULL: only a post with no slug of
    # its own in this locale falls back, so a post that has one is not *also*
    # reachable at its default-locale slug -- one post, one URL per locale.
    where("slug ->> ? IS NULL AND slug ->> ? = ?", locale.to_s, I18n.default_locale.to_s, slug).first
  end

  def all_related_posts
    forward_ids = PostRelation.where(post_id: id).select(:related_post_id)
    backward_ids = PostRelation.where(related_post_id: id).select(:post_id)
    Post.where(id: forward_ids).or(Post.where(id: backward_ids))
  end

  private

  # Raw jsonb hash, not the Mobility reader: see the comment above
  # `validate :title_present_in_any_locale`.
  def title_present_in_any_locale
    errors.add(:title, :blank) if read_attribute(:title).to_h.values.all?(&:blank?)
  end
end
