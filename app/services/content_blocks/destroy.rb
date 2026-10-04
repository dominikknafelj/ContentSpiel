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
  class Destroy < ApplicationService
    include OwnerPermissions

    def initialize(block, actor: Current.actor)
      @block = block
      @actor = actor
    end

    def call
      refused = owner_refusal(@block.owner) { |key| authorize!(key, @block) }
      return denied(refused, @block) if refused

      destroyed = ContentBlock.transaction do
        record_event("block.deleted", subject: @block)
        @block.destroy || raise(ActiveRecord::Rollback)
        # Same owner bump as `ContentBlocks::Save` (final fix wave, I3).
        @block.owner.touch
        # Drops the block's `media_usages` rows (media library design spec
        # §5.1): `refresh` computes none for a destroyed record.
        Media::UsageIndex.refresh(@block)
        # Its fields no longer count towards its owner's translation state.
        Translations::StateIndex.refresh(@block)
        true
      end

      return failure(@block) unless destroyed

      success(@block)
    end
  end
end
