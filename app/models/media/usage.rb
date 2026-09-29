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

  ROLES = %w[hero block_image rich_text].freeze

  belongs_to :media_asset, class_name: "Media::Asset"

  # `Page`, `ContentBlock` or `Post` -- never another `Media::Usage`, and
  # never `Media::Asset` itself. `Media::UsageIndex::OWNER_CLASSES` is the
  # single source of truth for which classes this actually covers; nothing
  # here re-validates that, since every row only ever comes from that class.
  belongs_to :owner, polymorphic: true

  validates :role, inclusion: { in: ROLES }
end
