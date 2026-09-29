# Rebuilds `media_usages` (design spec §3.2/§3.3) -- the only writer that
# ever touches that table. There is no incremental "add a row when a field
# changes" path: every write recomputes one owner's *entire* set of rows
# from that owner's current state and replaces them atomically, which is
# both simpler and safer than trying to diff an old body against a new one
# for every possible way a reference can appear, move or disappear.
#
# `.refresh(owner)` is called from a save/destroy service's own transaction
# (design spec §5.1: `Pages::Save`, `ContentBlocks::Save`, `Posts::Save`
# and the destroy services -- wired up in a later task, not this one) --
# never from a model callback, so a script or a migration can also call it
# directly without needing to go through a whole record save.
class Media::UsageIndex
  # The only owner kinds a usage row can ever belong to (design spec §3.2's
  # "owner_type / owner_id: Page, ContentBlock or Post"). `.refresh` on
  # anything else -- a `SiteSetting`, a `Tag`, whatever else might someday
  # be handed to it by mistake -- is a deliberate no-op rather than a raise:
  # callers that generically call `Media::UsageIndex.refresh(record)` after
  # any save shouldn't have to first check what kind of record it is.
  OWNER_CLASSES = [ Page, ContentBlock, Post ].freeze

  class << self
    # Recomputes `owner`'s own rows and replaces them in one transaction:
    # delete whatever's currently stored for this owner, then insert
    # whatever its current state actually implies. A destroyed owner (its
    # save/destroy service calls this from an `after_destroy`-equivalent
    # step) is handled by simply never computing any rows for it -- `owner
    # .destroyed?` short-circuits `#rows_for` -- rather than by reading
    # (still-present, since `destroy` only freezes the in-memory object)
    # attributes off a record that no longer exists in the database and
    # would otherwise happily re-insert rows for it.
    def refresh(owner)
      return unless media_managed?(owner)

      rows = owner.destroyed? ? [] : rows_for(owner)

      Media::Usage.transaction do
        Media::Usage.where(owner: owner).delete_all
        Media::Usage.insert_all!(rows) if rows.any?
      end
    end

    # The whole table, from scratch: every `Page`, `ContentBlock` and `Post`
    # gets `.refresh`ed in turn. Equivalent to (but far cheaper than) simply
    # truncating `media_usages` and running every owner's `.refresh` one at
    # a time, since it's implemented as exactly that -- `find_each` so a
    # large table is streamed in batches rather than loaded whole, backing
    # the `media:reindex` rake task and the migration that first populates
    # this table (Task 4).
    def rebuild_all
      OWNER_CLASSES.each { |klass| klass.find_each { |owner| refresh(owner) } }
    end

    private

    def media_managed?(owner) = OWNER_CLASSES.any? { |klass| owner.is_a?(klass) }

    # Every row `owner`'s *current* state implies -- not persisted, not
    # diffed against what's already stored; `.refresh` above owns the
    # replace-in-a-transaction part. Each owner kind contributes at most one
    # of the three shapes below; a `ContentBlock` is the only owner that can
    # ever contribute both `block_image` and `rich_text` rows (from
    # different block types in practice, but nothing here assumes that --
    # an owner with both a `media_asset_id` and a non-blank body would
    # simply get both).
    def rows_for(owner)
      now = Time.current
      rows = []
      rows.concat(hero_rows(owner, now)) if owner.is_a?(Page)
      rows.concat(block_image_rows(owner, now)) if owner.is_a?(ContentBlock)
      rows.concat(rich_text_rows(owner, now)) if owner.is_a?(ContentBlock) || owner.is_a?(Post)
      rows
    end

    # A page's hero (design spec §3.3): `pages.hero_media_asset_id`, not
    # per-locale (a page has exactly one hero image, whatever locale it's
    # viewed in -- only its alt text, `hero_alt`, is translated), so `locale`
    # is nil.
    def hero_rows(page, now)
      asset_id = page.hero_media_asset_id
      return [] unless asset_id

      [ row(asset_id: asset_id, owner: page, role: "hero", locale: nil, now: now) ]
    end

    # An image block's own attachment (design spec §3.3):
    # `content_blocks.media_asset_id`, also not per-locale for the same
    # reason -- one image per block, only its `alt`/`caption` overrides are
    # translated. `nil` for every other block type (`media_asset_id` is
    # only ever set on an `image` block), so this is safe to call
    # unconditionally for any `ContentBlock`.
    def block_image_rows(block, now)
      asset_id = block.media_asset_id
      return [] unless asset_id

      [ row(asset_id: asset_id, owner: block, role: "block_image", locale: nil, now: now) ]
    end

    # Every `image` node's `asset_id` in every locale of `owner`'s rich-text
    # body (design spec §3.3), one row per (asset, locale) pair -- the same
    # image referenced from two locales' documents gets two rows, and two
    # different images referenced from the same locale's document each get
    # their own row.
    #
    # Reads `read_attribute(:body)` -- the raw, all-locales-at-once Mobility
    # jsonb Hash (`{ locale => document }`) -- rather than `body_document
    # (locale:)`, which only ever answers for one already-current locale at
    # a time (`HasRichTextBody`'s own comment: "everything outside the
    # models reads... through #body_document/#assign_body", but this *is*
    # inside the models' own concern's territory -- indexing every locale at
    # once is exactly the case that reader doesn't cover). Not every owner
    # this is called for actually has a `body` column with real content --
    # an `image`/`post_list` block still has one (`HasRichTextBody` is
    # included unconditionally), just an empty `{}` -- so this naturally
    # produces no rows for them without needing to check `block_type` first.
    def rich_text_rows(owner, now)
      bodies = owner.read_attribute(:body)
      return [] unless bodies.is_a?(Hash)

      bodies.flat_map do |locale, doc|
        next [] unless doc.is_a?(Hash)

        image_asset_ids(doc).map { |asset_id| row(asset_id: asset_id, owner: owner, role: "rich_text", locale: locale, now: now) }
      end
    end

    # `RichText::Document#references` returns a Set of `[type_name,
    # attribute_name, value, *scope]` tuples (`RichText::Schema
    # .reference_key`) -- one per referencing attribute actually present in
    # the document, already deduplicated within it. The `image` node's
    # `asset_id` attribute (`RichText::BuiltIns`) is registered with a bare
    # `reference: true` (no scope), so its tuple is always exactly
    # `["image", "asset_id", <asset id>]`; every other reference kind in the
    # schema today (`internalLink`'s `target_id`, scoped by `target_type`)
    # has a different `type_name`/`attribute_name` pair and is filtered out
    # here rather than by this class knowing the full registry.
    def image_asset_ids(doc)
      RichText::Document.new(doc).references.filter_map do |type_name, attribute_name, value, *|
        value if type_name == "image" && attribute_name == "asset_id"
      end
    end

    def row(asset_id:, owner:, role:, locale:, now:)
      {
        media_asset_id: asset_id,
        owner_type: owner.class.polymorphic_name,
        owner_id: owner.id,
        role: role,
        locale: locale,
        created_at: now,
        updated_at: now
      }
    end
  end
end
