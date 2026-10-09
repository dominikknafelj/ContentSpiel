module ContentBlocks
  # Permanently removes one block (spec §7's "No trash" interim state,
  # global constraints) -- unlike a page's purge (`Trash::Purge`), there is no "refuse if
  # it has children" rule to enforce first: a block has no descendants of
  # its own, so this is a plain `destroy` wrapped in the same
  # `ApplicationService::Result` shape every other write goes through
  # (global constraints' "writes go only through services"), which is what
  # gives it the same `authorize!`/`record_event` attachment points
  # (`ContentBlocks::Save`/`Reorder`'s own) rather than a bare model call
  # the admin controller would otherwise have no policy hook for.
  #
  # Deleting a block is editing its owner: `<owner>.edit`, plus
  # `<owner>.publish` on a published owner (`ContentBlocks::
  # OwnerPermissions`). `block.deleted` is recorded before the destroy, in
  # its transaction, so the snapshot is the block's last state.
  #
  # A section has two forms of delete (sections spec §3.3), and the "no
  # descendants" above is no longer true of it. With its blocks (the
  # default): each block in it is destroyed first, with its own callbacks,
  # then the section. Or `keep_blocks: true`: the blocks are lifted to the
  # top level at the section's place, then the section alone goes. Either
  # way it is ONE `block.deleted` event, on the section, whose metadata
  # names the blocks (`deleted_block_ids` or `kept_block_ids`, decision D7).
  # The foreign key from a block to its section stays NO ACTION: it is this
  # service, not the database, that empties a section before removing it, so
  # a delete around the service is refused rather than cascading. A
  # section's delete takes the page's row lock first (`Structure#lock_owner`,
  # decision D14): a block added to it by another tab meanwhile is either in
  # the list read below or waits and is refused its vanished section.
  #
  # So does every other delete (fix rounds 1 and 2), for the order of
  # locks: every write to a page's blocks takes the page's row and then
  # block rows (`ContentBlocks::Save#call` has the deadlock this avoids --
  # a lift and a renumbering write top-level blocks under that lock, so a
  # top-level block's delete is no exception). The column a block leaves is
  # renumbered under the same lock a fold into that column holds.
  #
  # Positions are counted per container, so the gap a deleted block leaves
  # in a section's column, and the one a section leaves at the top level,
  # are closed. A top-level block that isn't a section still leaves its gap,
  # as it always did.
  class Destroy < ApplicationService
    include OwnerPermissions
    include Structure

    def initialize(block, keep_blocks: false, actor: Current.actor)
      @block = block
      @keep_blocks = keep_blocks
      @actor = actor
    end

    def call
      refused = owner_refusal(@block.owner) { |key| authorize!(key, @block) }
      return denied(refused, @block) if refused

      destroyed = ContentBlock.transaction do
        lock_owner(@block.owner)
        # `reload`: read under the lock, whatever the caller had loaded.
        inside = @block.container? ? @block.section_blocks.reload.to_a : []
        metadata = {}
        if inside.any?
          metadata = { (@keep_blocks ? "kept_block_ids" : "deleted_block_ids") => inside.map(&:id) }
          @keep_blocks ? lift(inside) : inside.each { |block| block.destroy || raise(ActiveRecord::Rollback) }
        end
        record_event("block.deleted", subject: @block, metadata: metadata)
        @block.destroy || raise(ActiveRecord::Rollback)
        # Same owner bump as `ContentBlocks::Save` (final fix wave, I3).
        @block.owner.touch
        # Drops the block's `media_usages` rows (media library design spec
        # §5.1): `refresh` computes none for a destroyed record.
        [ @block, *(inside unless @keep_blocks) ].each { |block| Media::UsageIndex.refresh(block) }
        # Its fields no longer count towards its owner's translation state.
        # One refresh covers the blocks that went with a section too: a
        # block's state is its owner's, recomputed from the blocks left.
        Translations::StateIndex.refresh(@block)
        renumber(@block.owner.content_blocks.in_column(@block.section_id, @block.section_column)) if inside.any? || @block.section_id
        true
      end

      return failure(@block) unless destroyed

      success(@block)
    end

    private

    # "Remove section, keep blocks" (sections spec §3.3): the blocks take the
    # section's place at the top level in reading order -- column 1's, then
    # column 2's -- and everything after them moves down. The section itself
    # still stands at this point; it goes right after, and the positions are
    # closed up once it has. (It is written too, with the nils it already
    # has: one loop for the whole top level.) A row already where it belongs
    # -- the blocks before the section -- isn't written: fewer rows held.
    def lift(inside)
      top = @block.owner.content_blocks.top_level.reorder(:position, :id).to_a
      at = top.index(@block)
      (top[0...at] + inside + top[at..]).each_with_index do |block, index|
        next if block.section_id.nil? && block.position == index

        block.update_columns(section_id: nil, section_column: nil, position: index) # version: none (the owner is touched below, and a live page's after_commit bumps)
      end
    end
  end
end
