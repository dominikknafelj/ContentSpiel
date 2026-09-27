class Post < ApplicationRecord
  extend Mobility
  include SlugGeneration
  include Publishable

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

  validates :title, presence: true
  validates :slug, presence: true
  validates :role_type, inclusion: { in: ROLE_TYPES.keys }, allow_blank: true
  validate :slug_is_unused_in_every_locale

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
      #
      # The message itself names the locale too, not just the field: a slug
      # here can arrive via `SlugGeneration`'s default-locale fallback rather
      # than anything the editor typed into this tab (Task 8c), so "has
      # already been taken" alone would send them looking at the wrong one.
      errors.add(accessor, :taken, message: "has already been taken in #{locale.to_s.upcase}") if taken
    end
  end
end
