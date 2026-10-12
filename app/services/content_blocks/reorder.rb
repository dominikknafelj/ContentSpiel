module ContentBlocks
  # Rewrites the order of one container of a page's blocks to `ordered_ids`
  # (spec §7.2). Unlike pages (`Page::TreeRanking`), a block reorder has no
  # "rank among siblings" semantics to reconstruct -- the caller already
  # hands over the exact, complete order -- so this only has to check that
  # order names exactly the container's blocks before writing it out.
  #
  # Reordering blocks is editing their owner: `<owner>.edit`, plus
  # `<owner>.publish` on a published owner (`ContentBlocks::
  # OwnerPermissions`). `@page` may be a post too -- any block owner.
  #
  # ONE CONTAINER PER CALL (sections spec §3.3). `section`/`column` name it:
  # nil and nil the page's own list, otherwise one column of one section.
  # `ordered_ids` is that container's complete new order. An id in it that
  # sits in another container now is MOVED here -- but only if `moved_from`
  # says where the caller believes it is, and it is there. That is the whole
  # guard against a stale screen: a block someone else moved, deleted or
  # folded away in the meantime makes the call a failure (`STALE`,
  # `NO_COLUMN`) and nothing is written; the editor's list is redrawn.
  # A two-argument call is what it always was: the page's top-level order.
  #
  # Positions are counted per container (sections spec §3.1), so a move
  # writes two of them: the target is numbered from `ordered_ids`, and each
  # container a block left is closed up (`Structure#renumber`).
  #
  # THE PAGE'S ROW IS LOCKED FIRST, by every call -- the plain top-level
  # reorder that names no section too (`Structure#lock_owner`). Two reasons,
  # the same two as in `ContentBlocks::Save#call`. What is judged is what
  # the other tab committed: one tab folds a section to two columns while
  # another drops a block into its third, and whichever comes second reads
  # the first one's rows -- the drop is refused with `NO_COLUMN`, or the
  # fold takes the dropped block along; no block ends in a column that
  # doesn't exist. And there is one order of locks for a write to a page's
  # blocks, the page's row and then block rows: this service used to write
  # block rows and then take the page's at the `touch`, the other way round
  # from a fold, a lift or a renumbering, which write the very rows a
  # top-level reorder does -- two transactions each holding what the other
  # waits for, and Postgres ends one with `ActiveRecord::Deadlocked`. It
  # costs one short query and no new waiting: a reorder that changed
  # anything always took this row, only later.
  #
  # One event whatever moved (decision D7): `block.reordered` on the page,
  # its `field_changes` the container's order before and after, and for a
  # call that names a section or moves a block its metadata `section_id`,
  # `column` (the container; both absent for the page's own list) and
  # `moved_block_ids`. The action never coalesces (`Audit::Coalescer`: only
  # `*.updated` does), so no move's metadata is lost to an open row.
  class Reorder < ApplicationService
    include OwnerPermissions
    include Structure

    # A block isn't where the caller's screen has it: it was moved or deleted
    # meanwhile, came from a container `moved_from` doesn't name, or the
    # order leaves out a block that has arrived since.
    STALE = "The blocks have changed since this screen loaded"
    # The target isn't there: the section was deleted (or isn't one), or its
    # layout no longer has that column.
    NO_COLUMN = "That section or column no longer exists"
    # A section among the blocks moved into a column (sections spec §3.2).
    NESTED = "A section can't go inside a section"
    # The two-argument call's own refusal, as it always read: an order of
    # the page's list that names a stranger, a block twice or not all of them.
    NOT_THE_LIST = "The new order must list exactly this page's blocks"

    def initialize(page, ordered_ids, section: nil, column: nil, moved_from: {}, actor: Current.actor)
      @page = page
      @ordered_ids = Array(ordered_ids).map(&:to_i)
      @section_id = (section.is_a?(ContentBlock) ? section.id : section).presence&.to_i
      @column = column.presence&.to_i
      # `{ block id => [ section id, column ] }`, nil and nil for the top
      # level. Keys and values arrive as a request sent them (strings, blank
      # for "none"); anything that isn't a hash of the two keys reads as the
      # top level, which the block is then found at or not -- never an
      # exception for a forged value.
      @moved_from = moved_from.to_h.to_h do |id, from|
        from = from.is_a?(Hash) ? from.symbolize_keys : {}
        [ id.to_i, [ from[:section_id].presence&.to_i, from[:column].presence&.to_i ] ]
      end
      @actor = actor
    end

    def call
      refused = owner_refusal(@page) { |key| authorize!(key, @page) }
      return denied(refused, @page) if refused

      problem = nil
      ContentBlock.transaction do
        lock_owner(@page)
        # `Rollback` before anything is written. Inside another service's
        # transaction (`ContentBlocks::Duplicate`) this block joins it and
        # the raise only leaves the block: the failure returned below is
        # what tells that caller to roll back.
        problem = refusal
        raise ActiveRecord::Rollback if problem

        before = members.reorder(:position, :id).ids
        blocks = @page.content_blocks.where(id: @ordered_ids).index_by(&:id)

        # `update_columns`, not `update`/`save`: block order doesn't affect any
        # URL (unlike a page's position, which the canonical-post-page ranking
        # in `PublicSite::Paths.canonical_page` reads), so there is nothing here
        # that needs a callback to react to a position change, and no reason to
        # re-run validations on rows nobody actually edited. The same goes for
        # the two placement columns of a moved block: `#refusal` has checked,
        # under the lock, what `ContentBlock#section_rules` would (the section
        # is this page's, is a container, has the column; no section goes in),
        # and a block's `updated_at` -- its autosave base -- must not move
        # because it was dragged: its open form would be refused as stale.
        @ordered_ids.each_with_index do |id, index|
          blocks[id].update_columns(section_id: @section_id, section_column: @column, position: index) # version: none (the owner is touched below: its after_commit bumps where its rows are what the site shows, and a page with a copy shows the copy)
        end
        @moved_from.values.uniq.each { |section_id, column| renumber(@page.content_blocks.in_column(section_id, column)) }

        # The owner is the subject: the order is a property of the page or
        # post, and its snapshot lists the block ids in their new order. An
        # order resubmitted unchanged isn't an event. (A move always changes
        # it: the moved block wasn't in `before`.)
        unless before == @ordered_ids
          # Same owner bump as `ContentBlocks::Save` (final fix wave, I3);
          # an unchanged order is no edit, so it's no bump either. The
          # touch is also what moves the public content version for a live
          # page (`Publishable#bump_public_version_when_live`).
          @page.touch
          record_event("block.reordered", subject: @page, field_changes: { "content_block_ids" => [ before, @ordered_ids ] }, metadata: metadata)
        end
      end

      problem ? failure(@page, [ problem ]) : success(@page)
    end

    private

    # A call that names a section or moves a block, as against the page's
    # own order: it answers a mismatch with `STALE` and says where in its
    # event.
    def structural? = @section_id.present? || @moved_from.any?

    # The container's blocks as they are now: a fresh query each time, read
    # under the lock.
    def members = @page.content_blocks.in_column(@section_id, @column)

    # The first reason this call can't be honoured, or nil. Everything is
    # looked up among `@page.content_blocks`, so another page's block or
    # section is simply not found: a stranger's id is never moved in, and
    # never tells a caller whether it exists.
    def refusal
      if @section_id
        section = @page.content_blocks.find_by(id: @section_id)
        return NO_COLUMN unless section&.container? && @column&.between?(1, section.column_count)
      elsif @column
        return NO_COLUMN
      end

      moving = @page.content_blocks.where(id: @moved_from.keys).index_by(&:id)
      return NESTED if @section_id && moving.values.any?(&:container?)

      # The order is the container's blocks plus the announced arrivals,
      # each once: a block that arrived unannounced, one the screen doesn't
      # know of, and one named twice all fail here.
      listed_exactly = @ordered_ids.uniq.size == @ordered_ids.size && @ordered_ids.to_set == (members.ids + @moved_from.keys).to_set
      # Each arrival is where the caller said -- and that is somewhere else:
      # a "move" from the target itself is a screen that is behind.
      where_expected = @moved_from.all? { |id, from| moving[id] && [ moving[id].section_id, moving[id].section_column ] == from && from != [ @section_id, @column ] }
      return nil if listed_exactly && where_expected

      structural? ? STALE : NOT_THE_LIST
    end

    def metadata
      return {} unless structural?

      { "section_id" => @section_id, "column" => @column, "moved_block_ids" => @moved_from.keys.presence }.compact
    end
  end
end
