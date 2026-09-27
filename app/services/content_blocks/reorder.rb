module ContentBlocks
  # Rewrites a page's block order to `ordered_ids` (spec §7.2). Unlike pages
  # (`Page::TreeRanking`), a block reorder has no "rank among siblings"
  # semantics to reconstruct -- the caller already hands over the exact,
  # complete order -- so this only has to check that order names exactly this
  # page's blocks before writing it out.
  class Reorder < ApplicationService
    def initialize(page, ordered_ids, actor: Current.actor)
      @page = page
      @ordered_ids = Array(ordered_ids).map(&:to_i)
      @actor = actor
    end

    def call
      authorize!(:reorder, @page)

      blocks = @page.content_blocks.index_by(&:id)
      unless blocks.keys.to_set == @ordered_ids.to_set
        return failure(@page, [ "The new order must list exactly this page's blocks" ])
      end

      # `update_columns`, not `update`/`save`: block order doesn't affect any
      # URL (unlike a page's position, which the canonical-post-page ranking
      # in `PublicSite::Paths.canonical_page` reads), so there is nothing here
      # that needs a callback to react to a position change, and no reason to
      # re-run validations on rows nobody actually edited.
      ContentBlock.transaction do
        @ordered_ids.each_with_index { |id, index| blocks[id].update_columns(position: index) }
      end

      record_event(:content_blocks_reordered, page: @page)
      success(@page)
    end
  end
end
