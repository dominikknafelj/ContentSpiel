module Admin
  module Answers
    # The answers to a block write that went through, one method per action of
    # `Admin::ContentBlocksController`. Each ends with the publishing chip
    # (`PublishingStreams`): a write on a live page is an unpublished change.
    class BlockSaved
      include BlockDrawing

      # An add (spec §5.1, sections spec §4.2). At the top level, the new card
      # appended to the list. Into a column, the block's form and its tile
      # (`tile_streams`), the form marked to open at once (spec §4.3), and the
      # section's new count. Not the section's card: re-rendering it would
      # replace every other form in it, an unsaved edit included.
      def created(block, section:)
        drawn = section ? [ *tile_streams(block, open: true), *section_count_streams(section) ] : insertion_stream(block)
        Answer.new(streams: [ *drawn, *publishing_streams ], status: :created)
      end

      # A card's autosave. `autosave` is the shared answer of every autosaving
      # form (`Admin::AutosaveResponses#autosave_stream`: the status line, the
      # error slots, the new base, the toast), and `refused_media` the image
      # field put back to the stored image when a choice was refused
      # (`Admin::MediaFields`). After them: the tile's line for a block in a
      # section, the icon of a type whose icon follows its block, and for a
      # section what its save changed (`section_save_streams`).
      def updated(block, autosave:, layout_before:, columns_before:, refused_media: nil)
        streams = [ *autosave ]
        streams << refused_media if refused_media
        streams << tile_summary_stream(block, invalid: false) if block.section_id
        streams.concat(block_icon_streams(block)) if block.definition&.icon_follows_block?
        streams.concat(section_save_streams(block, layout_before: layout_before, columns_before: columns_before)) if block.container?
        Answer.new(streams: [ *streams, *publishing_streams ], status: :ok)
      end

      # A delete (`removal_streams`). The notes on what was deleted are gone
      # with it (`Notes::Remove`): the header's number, the markers and the
      # next delete dialog's warning are told with the same answer, through the
      # page's one copy of the counts.
      def removed(block, kept_ids:, section:)
        counts = Admin::NotesScreen::CountsComponent.new(counts: Notes::Counts.for_container(context.page, user: context.viewer), id: "notes-counts")
        Answer.new(streams: [ *removal_streams(block, kept_ids, section), turbo_stream.replace("notes-counts", counts), *publishing_streams ], status: :ok)
      end

      # A reorder. A STRUCTURAL one (it named a section or moved a block
      # between containers) is answered with each moved block in its new shape
      # (`move_streams`); the browser has moved the element already, and what
      # it cannot do is turn a card into a tile and a form under the lanes, or
      # back. An order of the page's own list gets the Undo toast instead
      # (`reorder_undo_streams`).
      def reordered(origins:, structural:, before:, undo:, undo_url:)
        status = turbo_stream.replace(REORDER_STATUS_ID, Admin::Ui::SaveStatusComponent.new(id: REORDER_STATUS_ID, state: :saved, at: Time.current))
        drawn = structural ? move_streams(origins) : reorder_undo_streams(before, undo: undo, undo_url: undo_url)
        Answer.new(streams: [ status, *drawn, *publishing_streams ], status: :ok)
      end

      # A copy, put directly after its source by `ContentBlocks::Duplicate`.
      # At the top level its card is inserted right after the source's
      # (`insertion_stream` with the source), never appended at the end; a
      # section's card comes with its lanes, tiles and forms (`card_for`). The
      # copy of a block in a column is in that column, and is drawn there
      # (`copy_tile_streams`): the page's list is not where it is.
      def duplicated(copy, source:)
        drawn = copy.section_id ? copy_tile_streams(copy, source) : insertion_stream(copy, source)
        Answer.new(streams: [ *drawn, *publishing_streams ], status: :created)
      end

      private

      # An Undo toast follows a reorder that changed something: a PATCH of the
      # order as it was (`undo_url`, built by the action from the order it read
      # before the service ran). The answer to THAT request (`undo`) re-renders
      # the list (`update`, so the list element itself, the Sortable container,
      # stays), since unlike a drop the browser's DOM isn't already in the
      # order the server now has; and it gets a plain confirmation with no Undo
      # of its own, so two orders can't be bounced between forever.
      def reorder_undo_streams(before, undo:, undo_url:)
        return [ blocks_list_stream, toast_stream("Order restored.") ] if undo
        return [] if top_level_blocks.ids == before

        [ toast_stream("Block order changed.", kind: :undo, action: { label: "Undo", method: :patch, url: undo_url }) ]
      end

      # One toast appended to the layout's `#toasts` region, as
      # `Admin::AutosaveResponses#toast_stream` draws it.
      def toast_stream(message, kind: :success, action: nil, id: nil)
        turbo_stream.append("toasts", Admin::Ui::ToastComponent.new(message: message, kind: kind, action: action, id: id))
      end
    end
  end
end
