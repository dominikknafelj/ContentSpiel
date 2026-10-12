module AccessControl
  # The rule every write to a page's or post's content shares (access-control
  # design spec §3.1/§3.3): editing a block, a page's settings or a post is
  # `<owner>.edit` on the owner, and `<owner>.publish` too once the owner is
  # published (live or scheduled). Not because a save is public (it is not:
  # the site shows the published copy until "Publish changes"), but because
  # the person who may change a published record is the person who may
  # publish it (drafts spec D5), until "prepares" and "approves" are two
  # rights (release management). As in `Posts::Save`/`Pages::Save`. It lives
  # here, at the model layer, so that the services (`ContentBlocks::
  # OwnerPermissions`) and `Editing::Rights` both ask the SAME rule and cannot
  # drift; a model may not reach up into the services.
  #
  # Yields each key to check, answered by the caller with its own check;
  # returns the first key refused, or nil.
  module OwnerRule
    def self.refusal(owner)
      prefix = Checker::BLOCK_OWNER_PREFIX.fetch(owner.class.name)
      keys = [ "#{prefix}.edit" ]
      keys << "#{prefix}.publish" if owner.published_at.present?
      keys.find { |key| !yield(key) }
    end
  end
end
