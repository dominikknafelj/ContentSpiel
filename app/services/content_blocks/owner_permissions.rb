module ContentBlocks
  # The permission check every block write shares (access-control design
  # spec §3.1/§3.3): a block has no permissions of its own -- adding,
  # editing, reordering or deleting one is editing the page or post it
  # belongs to, so each needs `<owner>.edit` on that owner, never a
  # `create`/`delete` key (`AccessControl::Checker#resolve_block` raises on
  # `create` for a block for exactly this reason).
  #
  # Plus `<owner>.publish` when the owner is published (live or
  # scheduled): the spec §8 interim rule, as in `Posts::Save`/`Pages::
  # Save` -- a block edit on a published owner changes live content, and
  # only goes away with pending revisions (Phase 3).
  #
  # Yields each key to check; the service answers with its own
  # `authorize!(key, record)` -- the block (the checker maps it onto its
  # owner) or, for a reorder, the owner itself. Returns the refused key, or
  # nil.
  module OwnerPermissions
    private

    def owner_refusal(owner)
      prefix = AccessControl::Checker::BLOCK_OWNER_PREFIX.fetch(owner.class.name)
      keys = [ "#{prefix}.edit" ]
      keys << "#{prefix}.publish" if owner.published_at.present?
      keys.find { |key| !yield(key) }
    end
  end
end
