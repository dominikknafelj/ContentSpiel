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
    # Every `ContentBlocks::Save`, `Destroy`, `Reorder` and `Duplicate`
    # takes it, as the first statement of its transaction, whatever the
    # block: the page's row, then block rows, is the order of locks for a
    # page's blocks (`ContentBlocks::Save#call` has the deadlock a second
    # order made, and the list of writers that keep it: these four;
    # `Translations::Confirm`, which includes this module for a block's
    # field, because it writes the block's row and then the page's
    # `translation_states` rows; and `Tags::Merge`, `Trash::Purge` and
    # `RichText::ActionTextImport`, which lock their pages themselves).
    # Asking again inside the same transaction -- a duplicate's saves and
    # its reorder do -- is one short query for a lock already held.
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
        block.update_columns(position: index) unless block.position == index # version: none (the owner is touched below: its after_commit bumps where its rows are what the site shows, and a page with a copy shows the copy) # changes: none (every caller touches the owner, which marks it)
      end
    end
  end
end
