# One row per place a library asset is actually in use -- a page's hero, a
# block's image, or an `image` node inside a rich-text body (design spec
# §3.2). Purely derived: nothing ever builds a `Media::Usage` by hand
# outside `Media::UsageIndex`, which recomputes one owner's whole set of
# rows at once (`.refresh`) rather than keeping any single row in sync with
# whatever changed. See that class for how these rows are produced.
class Media::Usage < ApplicationRecord
  # Same reason `Media::Asset` needs it (see that model's own comment):
  # Zeitwerk demodulizes a namespaced model's inferred table name
  # (`Media::Usage` -> `usages`), so the real, `media_`-prefixed table name
  # has to be spelled out explicitly.
  self.table_name = "media_usages"

  # `published`: an image a current or pending published copy of the owner shows
  # (`Media::UsageIndex.refresh_published`); the owner is the page or post,
  # never a block, since a copy's block may no longer exist as a row.
  ROLES = %w[hero block_image rich_text published].freeze

  belongs_to :media_asset, class_name: "Media::Asset"

  # `Page`, `ContentBlock` or `Post` -- never another `Media::Usage`, and
  # never `Media::Asset` itself. `Media::UsageIndex::OWNER_CLASSES` is the
  # single source of truth for which classes this actually covers; nothing
  # here re-validates that, since every row only ever comes from that class.
  belongs_to :owner, polymorphic: true

  validates :role, inclusion: { in: ROLES }

  # Usages whose owner is still live (trash spec §4.1/§5.1). A block has no
  # trash state of its own, so a block-owned usage counts as kept when the
  # block's page or post is -- the second hop. Moving an image to the trash
  # asks this; purging one asks the plain `exists?` (any usage at all).
  scope :by_kept_owner, -> {
    kept_blocks = ContentBlock.where(owner_type: "Page", owner_id: Page.kept.select(:id))
      .or(ContentBlock.where(owner_type: "Post", owner_id: Post.kept.select(:id)))
    where(owner_type: "Page", owner_id: Page.kept.select(:id))
      .or(where(owner_type: "Post", owner_id: Post.kept.select(:id)))
      .or(where(owner_type: "ContentBlock", owner_id: kept_blocks.select(:id)))
  }
end
