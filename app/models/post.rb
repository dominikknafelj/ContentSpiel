class Post < ApplicationRecord
  extend Mobility
  include LocalizedSlug
  include Publishable
  include HasPublicPaths

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

  # Keeps `public_paths` in step with this post's canonical listing page and
  # slug (spec §5.4) -- the same duty `Page#sync_public_paths` performs for
  # pages, just without a subtree to cascade into: a post has no descendants
  # of its own, so `PublicSite::Paths.sync` (not `sync_subtree`) is enough.
  # Unconditional for the same reason `Page`'s callback is: `slug` is a
  # Mobility jsonb attribute, so there's no per-locale `saved_change_to?` to
  # narrow this with, and guessing wrong leaves a post unreachable at its own
  # URL.
  #
  # A tag gained or lost through `post.tags << tag`/`tag.destroy` doesn't
  # touch this row at all -- `has_many :through` writes `PostTag` directly --
  # so `PostTag`'s own `after_commit` callback is what re-syncs a post whose
  # *tag-filtered* canonical page depends on a change this callback never
  # sees.
  after_save { PublicSite::Paths.sync(self) }

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
