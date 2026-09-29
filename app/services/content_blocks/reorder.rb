module ContentBlocks
  # Rewrites a page's block order to `ordered_ids` (spec §7.2). Unlike pages
  # (`Page::TreeRanking`), a block reorder has no "rank among siblings"
  # semantics to reconstruct -- the caller already hands over the exact,
  # complete order -- so this only has to check that order names exactly this
  # page's blocks before writing it out.
  #
  # Reordering blocks is editing their owner: `<owner>.edit`, plus
  # `<owner>.publish` on a published owner (`ContentBlocks::
  # OwnerPermissions`). `@page` may be a post too -- any block owner.
  class Reorder < ApplicationService
    include OwnerPermissions

    def initialize(page, ordered_ids, actor: Current.actor)
      @page = page
      @ordered_ids = Array(ordered_ids).map(&:to_i)
      @actor = actor
    end

    def call
      refused = owner_refusal(@page) { |key| authorize!(key, @page) }
      return denied(refused, @page) if refused

      blocks = @page.content_blocks.index_by(&:id)
      unless blocks.keys.to_set == @ordered_ids.to_set
        return failure(@page, [ "The new order must list exactly this page's blocks" ])
      end

      before = @page.content_blocks.reorder(:position, :id).ids

      # `update_columns`, not `update`/`save`: block order doesn't affect any
      # URL (unlike a page's position, which the canonical-post-page ranking
      # in `PublicSite::Paths.canonical_page` reads), so there is nothing here
      # that needs a callback to react to a position change, and no reason to
      # re-run validations on rows nobody actually edited.
      ContentBlock.transaction do
        @ordered_ids.each_with_index { |id, index| blocks[id].update_columns(position: index) }

        # The owner is the subject: the order is a property of the page or
        # post, and its snapshot lists the block ids in their new order. An
        # order resubmitted unchanged isn't an event.
        unless before == @ordered_ids
          record_event("block.reordered", subject: @page, field_changes: { "content_block_ids" => [ before, @ordered_ids ] })
        end
      end

      success(@page)
    end
  end
end
