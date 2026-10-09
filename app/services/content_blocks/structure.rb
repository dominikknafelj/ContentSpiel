module ContentBlocks
  # What the services that change WHERE blocks are share (sections spec §3.3):
  # a create into a column, a move, a fold, a lift, a duplicate.
  module Structure
    private

    # The owner's row lock, taken first (decision D14). Two structural writes
    # on one page then run one after the other, each seeing what the other
    # committed: without it a fold to two columns and an add into column
    # three, started together, both pass their checks and leave a block in a
    # column the section no longer has. `pick`, not `owner.lock!`: the
    # caller's page object, with whatever it has preloaded, is left alone.
    #
    # Every `ContentBlocks::Save` and `Destroy` takes it, as the first
    # statement of its transaction, whatever the block: the page's row, then
    # block rows, is the one order of locks for a page's blocks
    # (`ContentBlocks::Save#call` has the deadlock a second order made).
    #
    # An owner that isn't saved yet has no row to lock, and nobody else can
    # be writing its blocks: nil, and no query.
    def lock_owner(owner)
      return unless owner.persisted?

      owner.class.where(id: owner.id).lock.pick(:id)
    end

    # Positions 0..n-1 over one container, in its current order.
    def renumber(relation)
      relation.reorder(:position, :id).each_with_index do |block, index|
        block.update_columns(position: index) unless block.position == index # version: none (every caller touches the owner, whose after_commit bumps for a live page)
      end
    end
  end
end
