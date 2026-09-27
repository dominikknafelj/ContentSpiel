module ContentBlocks
  # Permanently removes one block (spec §7's "No trash" interim state,
  # global constraints) -- unlike `Pages::Destroy`, there is no "refuse if
  # it has children" rule to enforce first: a block has no descendants of
  # its own, so this is a plain `destroy` wrapped in the same
  # `ApplicationService::Result` shape every other write goes through
  # (global constraints' "writes go only through services"), which is what
  # gives it the same `authorize!`/`record_event` attachment points
  # (`ContentBlocks::Save`/`Reorder`'s own) rather than a bare model call
  # the admin controller would otherwise have no policy hook for.
  class Destroy < ApplicationService
    def initialize(block, actor: Current.actor)
      @block = block
      @actor = actor
    end

    def call
      authorize!(:destroy, @block)

      return failure(@block) unless @block.destroy

      record_event(:content_block_destroyed, block: @block)
      success(@block)
    end
  end
end
