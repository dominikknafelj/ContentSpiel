module ContentBlocks
  # Creates or updates a content block (spec §7.2): the same translate-then-
  # assign shape as `Posts::Save`/`Pages::Save`, plus the append-on-create
  # rule a brand new block's `position` needs.
  #
  # Permissions: `<owner>.edit` (and `<owner>.publish` on a published
  # owner) -- see `ContentBlocks::OwnerPermissions`. A block's owner never
  # changes through here, so the check runs once, before anything is
  # assigned.
  #
  # An image block's library image (media library design spec §5.1):
  # `media_asset_id` in `attributes` sets, changes or (nil/"") clears it --
  # CS Studio's image field after a pick in the media picker, or Duplicate
  # copying the source's. Choosing one also needs `media.upload` and
  # an existing asset (`Media::Choosing`), so a duplicate of an image block
  # does too. Every save then refreshes the block's `media_usages` rows
  # (its image and its rich-text body's images) inside the transaction; an
  # image deleted in the meantime fails the save as "doesn't exist".
  #
  # Sections (sections spec §3.3). A NEW block may name the section and the
  # 1-based column it goes into (`section_id`, `section_column`); it lands at
  # the end of that column, and the model's placement rules answer a column
  # the section doesn't have. Both keys are ignored for a block that exists:
  # that one changes container only through `ContentBlocks::Reorder`. A
  # section saved with a layout of fewer columns takes the blocks of the
  # removed columns along into its last one (`#fold_removed_columns`), and
  # says which in the event's `folded_block_ids`. EVERY save takes the
  # page's row lock first (`Structure#lock_owner`, the comment in `#call`
  # says why), and a section is then re-read from its row before anything
  # is assigned (`#reread_container`).
  class Save < ApplicationService
    include OwnerPermissions
    include Media::Choosing
    include Structure

    TRANSLATED = %i[caption alt body].freeze

    def initialize(block, attributes: {}, translations: {}, actor: Current.actor)
      @block = block
      @attributes = attributes.to_h.symbolize_keys
      @translations = translations.to_h
      @actor = actor
    end

    def call
      refused = owner_refusal(@block.owner) { |key| authorize!(key, @block) }
      return denied(refused, @block) if refused

      image_refusal = media_choice_result(@block, :media_asset_id, :image)
      return image_refusal if image_refusal

      # `requires_new`: see `Pages::Save` -- a nested call's FK refusal
      # (rescued below) mustn't abort the caller's transaction.
      saved = ContentBlock.transaction(requires_new: true) do
        # The owner's row lock, the first statement of every save -- of a
        # block in a section, of a section, of a top-level block, new or
        # not. Two reasons.
        #
        # What is read under it is what the other writer committed: the new
        # block's column is checked, and the section's stranded blocks are
        # looked up, against rows no other save or delete of this page's
        # blocks can change until this one commits.
        #
        # And there is one order of locks for a write to a page's blocks:
        # the page's row, then block rows (fix rounds 1 to 3). A
        # fold, a lift, a section's delete and the renumbering that follows
        # one go page-first and then write other blocks' rows -- the blocks
        # in the section, and for a lift and a renumbering the top-level
        # blocks around it. A save used to go the other way: its own row,
        # then the page's at the `owner.touch` below. A tab typing in block
        # X while another removed a section and kept its blocks would each
        # hold what the other waits for, and Postgres ends one of them with
        # `ActiveRecord::Deadlocked`, a 500. "A top-level block is written
        # by no structural write" was the mistake of fix round 1: a lift
        # and a renumbering write exactly those. So no save is exempt.
        #
        # It costs one short query and no new waiting: this transaction
        # always took this row, at the touch; it only takes it earlier, so
        # two saves on one page queue here instead of there.
        #
        # The writers, all of which keep this order: this service,
        # `ContentBlocks::Destroy`, `ContentBlocks::Reorder` (every call,
        # the plain top-level order too -- it used to write block rows and
        # then touch the page), `ContentBlocks::Duplicate` (before the
        # saves and the reorder it runs), the tag merge (`Tags::Merge
        # #repoint_blocks`, which rewrites listing blocks), the purge of
        # a page (`Trash::Purge#purge_branch`, which deletes them),
        # `Translations::Confirm` for a block's field, and the one-off
        # `RichText::ActionTextImport` for a block's body.
        #
        # WHAT THE PAGE'S ROW STANDS FOR is every row a write to one of the
        # page's blocks may go on to write: the page itself (the touch),
        # the other blocks (a fold, a lift, a renumbering, a reorder) and
        # the page's DERIVED rows -- its `translation_states`, which
        # `Translations::StateIndex.refresh` upserts for the owner whatever
        # block was written. That last one is how `Translations::Confirm`
        # was missed at first: it writes a block's row and never the page's,
        # so "block rows and the page's row" did not name it, yet it wrote
        # the block and then the state rows while a delete or a duplicate
        # held the state rows and went on to the block. So the rule is not
        # about the `pages` row: a new writer of a block's row that writes,
        # in the same transaction, ANY other row of that page -- the page,
        # another block, a state row -- takes the page's row first.
        lock_owner(@block.owner)
        reread_container
        assign
        @block.save || raise(ActiveRecord::Rollback)
        folded = fold_removed_columns
        Media::UsageIndex.refresh(@block)
        # Editing a block is editing its owner (final fix wave, I3): bump
        # the owner's `updated_at` so everything ordered or labelled by it
        # (the dashboard's "Your drafts" "edited 2h ago", the posts list's
        # Updated column) sees the edit. `touch` runs no validations and no
        # save callbacks -- so not `Page#sync_public_paths` or closure_tree's
        # hierarchy rebuild, which a block edit can't affect -- only
        # `after_touch`/commit callbacks: a live owner's `after_commit`
        # moves the public content version (`Publishable`).
        @block.owner.touch
        # The touch comes BEFORE the state refresh: it takes the owner's row
        # lock, so a second editor's block save on the same page waits here
        # and its refresh then reads this transaction's committed rows,
        # instead of both computing the owner's state from their own snapshot
        # and the later upsert winning with a value that ignores the other's
        # change (final review A, M2). `ContentBlocks::Destroy` does the same.
        # A block's fields roll up into its owner's stored translation state
        # (`translation_states`), so this refreshes the page or post.
        Translations::StateIndex.refresh(@block)

        created = @block.previously_new_record?
        changes = Audit::Snapshot.field_changes_for(@block)
        # A fold is an event even when the save changed no field of the
        # section itself (decision D7: no action of its own, the section's
        # `block.updated` names the blocks that moved).
        #
        # And a fold is never coalesced into the section's open
        # `block.updated` row: an extension of a row leaves its `metadata` as
        # first written (`Audit.record`), so the ids would be lost exactly
        # when someone adjusts a section's look and then its layout. Only a
        # save that moved a block stands alone; every other one coalesces as
        # before, into the fold's row too, whose ids it does not touch.
        if created || changes.any? || folded.any?
          record_event(created ? "block.created" : "block.updated", subject: @block, field_changes: changes,
            metadata: (folded.any? ? { "folded_block_ids" => folded } : {}), coalesce: folded.empty?)
        end
        true
      end

      return failure(@block) unless saved

      success(@block)
    rescue ActiveRecord::InvalidForeignKey => e
      # The image, or an image the body embeds, was deleted between its
      # existence check and the write (final fix wave, M1; `Media::Choosing`).
      vanished_media_failure(e, @block, :media_asset_id, :image)
    end

    private

    # A section is judged as its row stands under the lock, not as the
    # caller's object was loaded before it (fix round 1). A second tab's copy
    # may say "two" where the row has since been widened to "four": assigning
    # `layout: "two"` to that copy changes nothing on it, so no UPDATE would
    # be issued and no field change recorded, yet the fold below would read
    # the copy's two columns and move the blocks -- a row that says four
    # columns with its blocks folded into two. Re-read, the same save is the
    # narrowing it looks like, and one that names no layout leaves it alone.
    #
    # The stale-save guard is not weakened: it runs in the controller, before
    # this service is called, against the record as that request loaded it
    # (`AutosaveResponses#refuse_stale_autosave`), and has refused or let the
    # save through by now. Nothing the caller assigned is lost either: a
    # service's block carries no unsaved change of its own, everything
    # arrives in `attributes` and `translations`.
    #
    # Only a persisted container: no other block's settings decide where
    # other blocks are. A section another tab deleted meanwhile is a failure
    # with a message, where the UPDATE of a missing row would have "saved".
    def reread_container
      return unless @block.persisted? && @block.container?

      @block.reload
    rescue ActiveRecord::RecordNotFound
      @block.errors.add(:base, "This block no longer exists")
      raise ActiveRecord::Rollback
    end

    def assign
      # `block_type` is assigned first: `settings`/`assign_settings` below
      # both need it to know which type's schema they're casting against.
      # `media_asset_id` is an image block's library image, already
      # checked by `#media_choice_result` (see the class comment).
      @block.assign_attributes(@attributes.slice(:block_type, :media_asset_id, :position))
      # Where a block is, is said once, when it is made: a persisted block
      # changes container only through `ContentBlocks::Reorder`, which checks
      # where the caller thought it was. A form that echoes the two keys
      # back on an ordinary save must not move anything.
      @block.assign_attributes(@attributes.slice(:section_id, :section_column)) if @block.new_record?

      @block.assign_settings(@attributes[:settings], locale: Locales.default) if @attributes.key?(:settings)

      @translations.each do |locale, values|
        values = values.to_h.symbolize_keys
        Mobility.with_locale(locale) { @block.assign_attributes(values.slice(*TRANSLATED).except(:body)) }
        # A rich-text JSON document, Hash or JSON String -- see the same line
        # in `Posts::Save#assign` for why it bypasses `assign_attributes`.
        @block.assign_body(values[:body], locale: locale) if values.key?(:body)
        @block.assign_settings(values[:settings], locale: locale) if values.key?(:settings)
      end

      assign_position
    end

    # Appends to the end of the block's own container -- the page's top-level
    # list, or one column of one section: `position` is counted per container
    # (sections spec §3.1) -- when no position was
    # given, on create only: the admin's "add a block" row submits no
    # position at all, and a nil here would otherwise reach Postgres as a
    # raw not-null violation instead of landing in the right spot. Once a
    # block is persisted, its position is only ever moved deliberately,
    # through `ContentBlocks::Reorder`.
    def assign_position
      return unless @block.new_record? && @attributes[:position].nil?

      @block.position = (@block.owner.content_blocks.in_column(@block.section_id, @block.section_column).maximum(:position) || -1) + 1
    end

    # A layout with fewer columns (sections spec §3.3): the blocks of each
    # removed column go to the end of the last remaining one, in column order.
    # A layout change never deletes a block. Inside the save's transaction,
    # under the owner's lock, so no block can arrive in a removed column
    # between the read and the write.
    #
    # Decided from the rows, not from the layout this object had when it was
    # loaded: a second tab's copy of the section may predate a widening (and
    # a block added to the new column since), and its save writes the old
    # layout back. Comparing "columns before" with "columns now" on that copy
    # sees no change and would strand the block. So every save of a section
    # asks which blocks sit beyond its layout -- one indexed query, none for
    # any other block. A section whose type is gone has no columns to fold
    # into (`column_count` 0) and is left as it is.
    def fold_removed_columns
      keep = @block.column_count
      return [] unless keep.positive?

      stranded = ContentBlock.where(section_id: @block.id, section_column: (keep + 1)..).reorder(:section_column, :position, :id).to_a
      return [] if stranded.empty?

      last = ContentBlock.in_column(@block.id, keep).maximum(:position) || -1
      stranded.each_with_index do |block, index|
        block.update_columns(section_column: keep, position: last + 1 + index) # version: none (the owner is touched below, and a live page's after_commit bumps)
      end
      stranded.map(&:id)
    end
  end
end
