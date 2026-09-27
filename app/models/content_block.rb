# One row per block on a page, in `position` order. All three block types share
# this table and are told apart by `block_type` -- the same
# single-model-plus-enum shape `Post` uses for its content types (page-tree
# design spec section 3). Which columns matter depends on the type: `body` for
# rich_text, `image` + `caption` for image, `settings` for post_list.
class ContentBlock < ApplicationRecord
  extend Mobility

  # jsonb columns holding one caption/alt text per locale; reading or writing
  # them goes through the current Mobility.locale. (`backend: :jsonb` is the
  # app-wide default set in config/initializers/mobility.rb, so it isn't
  # repeated here -- same as Post's and Page's translated plain-text
  # attributes.) `alt` only makes sense for `image` blocks, but it's declared
  # unconditionally since Mobility attributes are defined at class-load time.
  translates :caption, :alt

  # Rich text can't live in a jsonb column -- it has attachments and its own
  # table -- so `body` uses mobility-actiontext, which keeps one
  # ActionText::RichText row per locale. This replaces `has_rich_text :body`.
  translates :body, backend: :action_text

  belongs_to :page

  enum :block_type, { rich_text: 0, image: 1, post_list: 2 }

  # Shares its name with the `image` enum value without colliding: the enum
  # contributes the class-level scope `ContentBlock.image` and the predicate
  # `#image?`, while Active Storage contributes the instance reader `#image`.
  has_one_attached :image

  validates :block_type, presence: true

  # `position` is NOT NULL with a database default, which covers a block
  # created in code but not one whose position input the admin cleared: that
  # submits an empty string, which casts to nil and reaches Postgres as a raw
  # not-null violation rendered into the form. Validated so it comes back as a
  # form error instead.
  validates :position, presence: true

  # `settings` holds a post_list's query criteria (`content_type`, `tag`,
  # `limit`). Only `content_type` is checked, and only for post_list blocks: it
  # names a Post enum value, so a typo would silently return no posts at render
  # time instead of failing in the admin.
  validate :post_list_settings_reference_a_real_content_type, if: :post_list?

  # Every row of the admin's nested block form carries the same `settings`
  # inputs, whatever the block's type, so a rich_text block would otherwise be
  # saved holding `{"content_type" => "", "tag" => "", "limit" => ""}`. Those
  # blanks are not the same as "unset": the post_list partial asks
  # `settings["limit"].present?` and hands `settings["content_type"]` straight
  # to a `where` on an enum column.
  before_validation :discard_blank_settings

  # A post_list block's own criteria decide which posts have a canonical URL
  # under it (spec §5.3): adding, editing or removing one can hand a post its
  # first URL, move it to a different listing, or take it away entirely. Every
  # one of those has to re-run `PublicSite::Paths.canonical_page` for the
  # affected posts, not just the ones this block already lists -- edited to a
  # narrower `content_type`/`tag` still has to release the posts it no longer
  # matches. `sync_posts` re-derives each post's canonical page from scratch,
  # so it's called for both the block's current content type (after_save) and,
  # when a save or destroy changes which type that was, the previous one too.
  after_save :sync_listed_post_paths
  after_destroy :sync_listed_post_paths

  # The published posts this block is responsible for: its listing renders them
  # (newest first, trimmed to `settings["limit"]`) and its page serves a
  # permalink for each of them.
  #
  # An absent `content_type` means "every content type" -- the same reading
  # `post_list_settings_reference_a_real_content_type` below is written
  # against, and the one an editor gets by leaving the field empty in the
  # admin. It must therefore never reach `where`: `posts.content_type` is NOT
  # NULL, so `where(content_type: nil)` compiles to `content_type IS NULL` and
  # the block silently lists nothing at all.
  def listed_posts(include_unpublished: false)
    scope = include_unpublished ? Post.all : Post.published
    content_type = settings["content_type"]
    scope = scope.where(content_type: content_type) if content_type.present?

    # Tag names are matched case-insensitively: editors type "Rails" for a tag
    # stored as "rails". Trim to handle pasted tags with surrounding whitespace.
    tag = settings["tag"].to_s.strip
    if tag.present?
      scope = scope.where(id: PostTag.joins(:tag).where("LOWER(tags.name) = ?", tag.downcase).select(:post_id))
    end

    scope
  end

  # Whether this block's listing would include `post`, ignoring publication:
  # the same content-type-and-tag criteria `listed_posts` applies, minus its
  # `Post.published`/`Post.all` scope. `PublicSite::Paths.canonical_page`
  # (spec §5.3) needs this per-post rather than per-scope test to collect
  # every candidate listing for a post -- it then ranks them by the listing
  # page's publication, the block's specificity and tree order itself; the
  # *post's* own publication is the resolver's to gate (spec §6.3).
  # Kept deliberately in lockstep with `listed_posts` above: any criteria
  # change there has to land here too, or a post's listing and its canonical
  # URL would disagree about which page is responsible for it.
  def lists?(post)
    return false unless post_list?
    return false if settings["content_type"].present? && settings["content_type"] != post.content_type

    tag = settings["tag"].to_s.strip
    tag.blank? || post.tags.any? { |t| t.name.downcase == tag.downcase }
  end

  private

  # Every content type a post_list save or destroy could have handed a
  # canonical page to, or taken one away from: the block's content type as it
  # is now (skipped if this isn't -- or, on a save that changed `block_type`
  # away from post_list, no longer is -- a post_list block), and, only on a
  # save, the content type it matched *before* this save (skipped when that
  # doesn't apply either). `_before_last_save` accessors read back the value
  # from before the save that just ran regardless of whether that particular
  # attribute changed in it, which is exactly "before this edit" whether the
  # edit touched `settings`, `block_type`, both, or neither -- and after a
  # destroy they read back the value from the *previous* save instead, which
  # for an otherwise-untouched record is simply its current value, so
  # `post_list?` alone (still readable on a destroyed record; only mutation is
  # frozen) already covers that case without a second lookup.
  #
  # `nil` here means "every content type", the same reading `listed_posts`
  # and the settings validation give a blank `settings["content_type"]` --
  # `presence` is what keeps that blank from reaching `sync_posts` as `""`.
  def sync_listed_post_paths
    return unless post_list? || block_type_before_last_save == "post_list"

    content_types_to_resync.each { |content_type| PublicSite::Paths.sync_posts(content_type) }
  end

  def content_types_to_resync
    types = []
    types << settings["content_type"].presence if post_list?
    types << settings_before_last_save["content_type"].presence if block_type_before_last_save == "post_list"
    types.uniq
  end

  def discard_blank_settings
    self.settings = settings.to_h.compact_blank
  end

  def post_list_settings_reference_a_real_content_type
    content_type = settings["content_type"]

    # Absent means "every content type", which is a valid list.
    return if content_type.blank?
    return if Post.content_types.key?(content_type.to_s)

    errors.add(:settings, "content_type must be one of: #{Post.content_types.keys.join(', ')}")
  end
end
