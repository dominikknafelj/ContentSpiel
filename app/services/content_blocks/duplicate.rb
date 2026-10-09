module ContentBlocks
  # Duplicate (cs-studio spec §5.1; sections spec §3.3): a copy of one block
  # directly after it in its own container -- and, for a section, of every
  # block in it, into the same columns in the same order. It used to be built
  # in `Admin::ContentBlocksController#duplicate`; a section's copy is several
  # writes that must all land or none, which is a service's job.
  #
  # Every copy is saved through `ContentBlocks::Save`, so one place decides
  # what a new block needs: the image-choice rule (a copy of an image block
  # needs `media.upload`, `Media::Choosing`), the usage rows, the owner's
  # touch and translation state, and a `block.created` per copy. The copy is
  # then put after its source by `ContentBlocks::Reorder` (`block.reordered`),
  # as it always was. So a duplicated section is several events, not one
  # (sections plan, Q2). None of them coalesces (`Audit::Coalescer`: only
  # `*.updated` does), so each copy keeps its own row and the reorder its
  # metadata.
  #
  # What is copied: the type, both halves of its settings, every enabled
  # locale's caption, alt and body, and the image reference -- the copy shows
  # the same library asset; nothing is copied in the library, and the asset
  # can't be deleted while either block uses it.
  #
  # The page's row is locked first (`Structure#lock_owner`), before the saves
  # and the reorder, which each ask for it again inside this transaction and
  # have it already: one order of locks for every write to a page's blocks
  # (`ContentBlocks::Save#call`). The source is then read again from its row,
  # with the blocks in it: where it stands, and what a section holds, is what
  # the other tab committed, not what this request loaded before it waited.
  class Duplicate < ApplicationService
    include OwnerPermissions
    include Structure

    # audit: none (ContentBlocks::Save records block.created for every copy and ContentBlocks::Reorder block.reordered for its place)

    # The source was deleted between the request finding it and the lock.
    GONE = "This block no longer exists"

    def initialize(source, actor: Current.actor)
      @source = source
      @actor = actor
    end

    def call
      refused = owner_refusal(@source.owner) { |key| authorize!(key, @source) }
      return denied(refused, @source) if refused

      copy = nil
      stopped = nil
      refused_block = nil
      ContentBlock.transaction do
        lock_owner(@source.owner)
        stopped = reread_source
        raise ActiveRecord::Rollback if stopped

        stopped = save_copy(@source, section_id: @source.section_id, section_column: @source.section_column)
        copy = stopped.record
        refused_block = @source
        # In column and position order (`ContentBlock#section_blocks`), each
        # appended to the end of its column: the same columns, the same order.
        @inside.each do |inner|
          break unless stopped.ok?

          stopped = save_copy(inner, section_id: copy.id, section_column: inner.section_column)
          refused_block = inner
        end
        stopped = place_after_source(copy) if stopped.ok?
        # A nested save rolls back only its own savepoint (`requires_new`)
        # and a nested reorder nothing at all: this `Rollback` is what takes
        # the copies already made with it, and their events.
        raise ActiveRecord::Rollback unless stopped.ok?

        stopped = nil
      end

      return success(copy.reload) unless stopped
      return stopped unless stopped.denied?

      # A denial is the one event that must survive the rollback of the
      # write it refused (`ApplicationService#denied`), and the save that
      # refused wrote its `access.denied` inside the transaction above,
      # which has just taken it away with the copies made before it. So it
      # is recorded again here, outside, once, on the block whose copy was
      # refused. Which permission: the owner's keys were all held a moment
      # ago (the first lines of `#call`) and are asked once more in case
      # that changed; otherwise the only other thing a new block's save
      # refuses is the choice of its image (`Media::Choosing`).
      denied(owner_refusal(@source.owner) { |key| authorize!(key, @source) } || "media.upload", refused_block)
    end

    private

    # The source and the blocks in it, as their rows stand under the lock.
    # Returns the failure for a source that is gone, or nil. Nothing of the
    # caller's is lost by the reload: a source carries no unsaved change, it
    # is only read.
    def reread_source
      @source.reload
      @inside = @source.section_blocks.reload.to_a
      nil
    rescue ActiveRecord::RecordNotFound
      failure(@source, [ GONE ])
    end

    def save_copy(block, section_id:, section_column:)
      copy = ContentBlock.new(owner: block.owner, block_type: block.block_type, settings: block.settings, translated_settings: block.translated_settings)
      copy_translations(block, copy)
      # The image reference goes in through the service (final fix wave,
      # Minor 6), so it's saved in the same authorized, audited write -- and
      # the `block.created` snapshot shows it.
      attributes = { media_asset_id: block.media_asset_id, section_id: section_id, section_column: section_column }.compact
      ContentBlocks::Save.call(copy, attributes: attributes, actor: @actor)
    end

    # The save appended the copy to the end of its container; its place is
    # directly after the source, among the source's own siblings.
    def place_after_source(copy)
      siblings = @source.owner.content_blocks.in_column(@source.section_id, @source.section_column).reorder(:position, :id).ids - [ copy.id ]
      siblings.insert(siblings.index(@source.id) + 1, copy.id) # version: none (Array#insert, no SQL)
      ContentBlocks::Reorder.call(@source.owner, siblings, section: @source.section_id, column: @source.section_column, actor: @actor)
    end

    # Every locale's translated columns (`Save::TRANSLATED`, the one list
    # `TRANSLATED_COLUMNS` in `Admin::ContentBlocksController` derives from
    # too), copied literally (no fallback) from `source` onto `copy` --
    # `Mobility.with_locale` is what both the reader and the writer need for
    # a jsonb column (Locales.default note in `ContentBlocks::Save` explains
    # why the writer side can't take a `locale:` keyword directly the way a
    # jsonb reader can).
    #
    # `body` is the rich-text JSON document (tiptap spec §3.1), copied as
    # data through `body_document`/`assign_body` rather than the Mobility
    # reader/writer pair the other columns use: `assign_body` is the one
    # writer that refuses a "nothing" value instead of silently deleting the
    # locale (`HasRichTextBody#assign_body`). A document is copied verbatim, so a
    # duplicate's body is exactly the source's, and duplicating a duplicate
    # stays that way (the ActionText-era bug this method used to guard
    # against -- a re-rendered `trix-content` wrapper nesting itself on
    # every duplicate -- has no equivalent for plain JSON). A blank locale
    # is skipped rather than copied as an empty document.
    def copy_translations(source, copy)
      Locales.enabled.each do |code|
        Mobility.with_locale(code) do
          Save::TRANSLATED.each do |column|
            if column == :body
              document = source.body_document(locale: code)
              copy.assign_body(document, locale: code) unless document.blank?
            else
              copy.public_send("#{column}=", source.public_send(column))
            end
          end
        end
      end
    end
  end
end
