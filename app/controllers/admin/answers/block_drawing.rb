module Admin
  module Answers
    # What the block responders draw with (`BlockSaved`, `BlockRefused`,
    # `BlockGone`): the page editor's block list, a section's lanes, tiles and
    # panels, and the streams that put each right after a write. Everything is
    # read from the responder's `Context`, and every component is drawn there
    # with the page's holds.
    module BlockDrawing
      # The status line of the page's block list, which a reorder's answer
      # replaces.
      REORDER_STATUS_ID = "content-blocks-status"

      # The page's own list: the blocks outside any
      # section, which is what the block list shows as cards, what "first" and
      # "last" are counted among and what a reorder of the page names. A block
      # in a section's column has its `position` counted in that column, so it
      # is no part of this order. A fresh query each time it is asked: every
      # caller reads it after a service has written, but for the order a
      # reorder's Undo goes back to, which the action reads before it.
      def self.top_level_blocks(page) = page.content_blocks.top_level.reorder(:position, :id)

      # A section's layout as its type reads it: the schema's default where the
      # row stores none, as a section just made does, so that section's first
      # save of a background is no change of layout. Nil for a block that has
      # none. The action reads it before the save, `section_save_streams`
      # after.
      def self.stored_layout(block) = block.container? ? block.settings_object(locale: ::Locales.default)&.layout : nil

      def initialize(context)
        @context = context
      end

      private

      attr_reader :context

      def turbo_stream = context.turbo_stream

      def publishing_streams = PublishingStreams.for(context.page, view: context.view, url_options: context.url_options)

      def top_level_blocks = BlockDrawing.top_level_blocks(context.page)

      # The page's blocks as they are now: `reset` drops what the association
      # loaded before the action's service wrote.
      def fresh_outline = BlockOutline.new(context.page.content_blocks.reset)

      # The fixed slot every page editor renders once, up front
      # (`content-blocks-alert`), that a refusal and a gone block report into:
      # a failed add or move has no field of its own to blame, and a gone block
      # no card left to say it in.
      def picker_error_stream(errors)
        turbo_stream.replace("content-blocks-alert", partial: "admin/shared/field_errors", locals: { id: "content-blocks-alert", messages: errors })
      end

      # The whole block list, re-rendered in the server's order. The first card
      # has Move up disabled and the last Move down (`first:`/`last:`), as on a
      # page load.
      #
      # One outline for the whole list: a section's card draws the blocks in it
      # from the same array (`card_for`).
      def blocks_list_stream
        outline = fresh_outline
        blocks = outline.top_level
        cards = blocks.each_with_index.map { |block, index| context.render(card_for(block, first: index.zero?, last: index == blocks.size - 1, outline: outline)) }
        turbo_stream.update("content-blocks-list", html: context.safe_join(cards))
      end

      # A block in a section is a tile until it is opened, and the one line on
      # its tile is drawn from what the block holds: every
      # answer to its autosave redraws that line, so a tile never shows the
      # caption or the image of before the save. Its form may well be closed by
      # the time the answer is here, and then the tile is all there is to see.
      # A save refused as invalid says so on the tile (`invalid:`), for the same
      # reason: the error slots are in a form nobody may be looking at. Not a
      # denied save: that is no fault of the block's, and the error toast says
      # it.
      #
      # Only the summary is replaced, never the tile: the tile's button may hold
      # the focus and says which form is open (`aria-expanded`). A refused stale
      # save (409) and a deleted block (410) are answered without it: the first
      # has changed nothing and the second has no tile.
      def tile_summary_stream(block, invalid:)
        turbo_stream.replace(Admin::EditorScreen::TileSummaryComponent.dom_id(block),
          Admin::EditorScreen::TileSummaryComponent.new(block: block, locale: context.locale, invalid: invalid))
      end

      # A type whose icon follows its block (`icon ... for_block:`, the Note
      # block's kind) has the icon redrawn on the card's head and on the tile
      # with every answer to a save that went through, as the tile's line is:
      # neither is re-rendered by a save otherwise, and a kind chosen and saved
      # would keep the old kind's icon until a reload. Only the icon's span is
      # replaced, never the head or the face around it (the face may hold the
      # focus). Replacing an id that is not on the page (a block at the top
      # level has no tile) does nothing.
      def block_icon_streams(block)
        %i[card tile].map do |place|
          turbo_stream.replace(Admin::Ui::BlockIconComponent.dom_id(block, place),
            Admin::Ui::BlockIconComponent.new(definition: block.definition, place: place, block: block))
        end
      end

      # A block in a section is two elements: its tile,
      # which has the block's `dom_id` and is removed like a card, and its
      # form's panel under the lanes. The panel goes with it, and it can be the
      # very thing on screen: an unavailable block's panel has "Delete block…"
      # in it. Left behind it would stay open with no tile to close it from, its
      # Delete answering 410. `admin--editor--section` needs no telling: the
      # open form is whichever panel is showing, and none is.
      def panel_removal_streams(block)
        block.section_id ? [ turbo_stream.remove(Admin::EditorScreen::BlockCardComponent.panel_id(block)) ] : []
      end

      # A block's two halves inside a section, in the order
      # `admin--editor--section` needs them: the panel (its form) first, then
      # the tile that opens it. Either order would open the form (whichever
      # target connects second finds the other, `openIfNew`), but with the form
      # already there the tile is never on screen with nothing to open.
      #
      # `open:` marks both for a block just added: the panel `data-open`, which
      # is what the script acts on, and the tile's button as expanded, so it
      # does not say "collapsed" for the moment in between. `editable: true`:
      # the service has just allowed this actor the write.
      def tile_streams(block, open: false)
        section = block.section
        [ turbo_stream.append(Admin::EditorScreen::SectionCardComponent.panels_id(section), panel_component(block, open: open)),
          turbo_stream.append(Admin::EditorScreen::SectionLanesComponent.lane_id(section, block.section_column), tile_component(block, open: open)) ]
      end

      # The copy of a block that sits in a column (Duplicate, from its tile's
      # menu): its form under the section's lanes, then its tile directly after
      # the source's, where `ContentBlocks::Duplicate` put it (not the end of
      # the lane `tile_streams` appends to), and the section's two counts, which
      # a copy raises as an add does.
      #
      # NOT OPENED, unlike a block just added, which opens at once: an added block is empty and its form is what
      # the person came for; a copy already holds what its source holds, and
      # what follows a Duplicate is as often moving the copy as editing it.
      # Opening it would also close the form that is open in the section, which
      # may be the source's, mid-edit. The focus goes to the copy's menu
      # (`admin--editor--blocks#focusCopy`), from where it is opened, moved or
      # copied on.
      def copy_tile_streams(copy, source)
        section = copy.section
        [ turbo_stream.append(Admin::EditorScreen::SectionCardComponent.panels_id(section), panel_component(copy)),
          turbo_stream.after(ActionView::RecordIdentifier.dom_id(source), tile_component(copy)),
          *section_count_streams(section) ]
      end

      def panel_component(block, open: false)
        Admin::EditorScreen::BlockCardComponent.new(page: context.page, block: block, locale: context.locale, url_options: context.url_options,
          editable: true, placement: :panel, open: open, holds: context.holds)
      end

      def tile_component(block, open: false)
        Admin::EditorScreen::BlockTileComponent.new(page: context.page, block: block, locale: context.locale, url_options: context.url_options,
          editable: true, open: open, holds: context.holds)
      end

      # Each block a saved reorder moved between containers, in its new shape
      # and the count of every section that gained or
      # lost one. `origins` is the request's `moved_from`, which the service
      # has just found true: where each block was.
      #
      # - A card that went into a column becomes a tile, and its form a panel
      #   under that section's lanes.
      # - A tile that left its section becomes a card of the list, told whether
      #   it is the first or the last as on a page load; its panel goes.
      # - A tile that went to another section stays a tile, but its panel goes
      #   from the one section to the other.
      # - A tile that changed lanes inside its section keeps both. Only its
      #   panel's heading is rewritten, which names the column.
      #
      # THE BROWSER HAS ALREADY MOVED THE ELEMENT (`admin--editor--blocks#move`),
      # so the `replace` of the block's `dom_id` lands where it was dropped, and
      # nothing here says a position.
      #
      # THE ONE PLACE A FORM IS REPLACED BY A MOVE. Everything else that redraws
      # part of a section leaves its panels alone (`section_structure_streams`),
      # because a form holds what is typed and its place in the write queue. A
      # form can't be kept here: a card's is inside the card, a panel's is under
      # the lanes of the section it left. So the browser sends what the form
      # holds before the move, and doesn't send the move at all for a form that
      # did not end clean; the forms drawn here are new ones, with the block's
      # base as it is now, which a move leaves alone (`ContentBlocks::Reorder`
      # writes with `update_columns`).
      #
      # The old panel is removed first in every case but the last: for a card
      # the stream finds none, and a panel appended before the old one left
      # would be the second element with its id.
      def move_streams(origins)
        outline = fresh_outline
        # Every top-level block by id, not only the containers: a block moved
        # out of a section whose type is gone left a card that still counts
        # its blocks, in its delete dialog.
        sections = outline.top_level.index_by(&:id)
        top_level = outline.top_level
        touched = []

        streams = outline.reading_order.select { |block| origins.key?(block.id.to_s) }.flat_map do |block|
          from = origins.dig(block.id.to_s, "section_id").presence&.to_i
          touched.push(from, block.section_id)
          dom = ActionView::RecordIdentifier.dom_id(block)
          old_panel = turbo_stream.remove(Admin::EditorScreen::BlockCardComponent.panel_id(block))

          if from == block.section_id
            [ turbo_stream.update(Admin::EditorScreen::BlockCardComponent.panel_title_id(block), Admin::EditorScreen::PanelTitleComponent.new(block: block)) ]
          elsif block.section_id
            [ old_panel,
              turbo_stream.append(Admin::EditorScreen::SectionCardComponent.panels_id(block.section), panel_component(block)),
              turbo_stream.replace(dom, tile_component(block)) ]
          else
            [ old_panel, turbo_stream.replace(dom, card_for(block, first: top_level.first == block, last: top_level.last == block, outline: outline)) ]
          end
        end

        streams + touched.compact.uniq.filter_map { |id| sections[id] }.flat_map { |section| section_count_streams(section, count: outline.blocks_in(section).size) }
      end

      # What leaves the screen with a deleted block: a top-level card; a tile
      # with its panel, and its section recounted; or a section's card,
      # replaced, when its blocks were kept, by their cards in the order they
      # now have at the top level, which is the reading order they had in it
      # (`ContentBlocks::Destroy#lift`).
      #
      # The cards are a block list's own (`card_for`): each a new form with the
      # block's base as it is now, registered with the write queue as it
      # connects. The forms they replace (the section's panels) go with the
      # section's card, and none of them holds anything the database does not
      # have: the request was not sent until the screen's write queue was empty
      # and every form clean (`admin--saving--queue-hold` on the "Remove
      # section, keep blocks" form, `SectionCardComponent#settled_screen_data`).
      # Waiting its turn in the queue would not be enough: the delete would go
      # ahead of the follow-up of a save still on the wire, and over a form
      # paused by a 409 (`test/system/admin/sections_removing_test.rb`, the two "Remove
      # section, keep blocks" tests about unsaved text). Each card is told
      # whether it is the list's first or last, as on a page load; its
      # neighbours are corrected in the browser (`admin--editor--blocks
      # #refreshMoveState`, on every change of the list's children).
      def removal_streams(block, kept_ids, section)
        id = ActionView::RecordIdentifier.dom_id(block)
        return [ turbo_stream.remove(id), *panel_removal_streams(block), *section_count_streams(section) ] if section
        return [ turbo_stream.remove(id) ] if kept_ids.empty?

        # One outline for all of them: `card_for` reads the page's blocks when
        # it is handed none, which would be once per lifted block.
        outline = fresh_outline
        ordered = outline.top_level
        cards = ordered.select { |lifted| kept_ids.include?(lifted.id) }.map do |lifted|
          context.render(card_for(lifted, first: ordered.first == lifted, last: ordered.last == lifted, outline: outline))
        end
        [ turbo_stream.replace(id, html: context.safe_join(cards)) ]
      end

      # A section's structure as the database has it now, for an answer that
      # must put right what this tab shows of it: a
      # save of the section that changed how many columns it has (a narrower
      # layout folds the blocks of the removed columns into the last one left,
      # `ContentBlocks::Save#fold_removed_columns`) and an add refused because
      # another tab removed the column it named.
      #
      # THE ONE REDRAW OF A SECTION'S LANES. Three things on screen say which
      # column a block is in, and they are brought up to date together or the
      # screen contradicts itself: the lanes with their tiles; the heading of
      # each block's form under them ("Image · column 2"), whether it is open
      # or not; and the head's column word and its count of blocks, with the
      # delete dialog's. So nothing draws the lanes alone.
      #
      # NEVER A PANEL. A block's form is in the page from the start and stays
      # (`Admin::EditorScreen::SectionCardComponent`): it may hold text that is
      # not saved, and it is registered with the write queue as the element it
      # is. The heading's text is rewritten inside the heading (`update`, with
      # `Admin::EditorScreen::PanelTitleComponent`, the words the panel itself
      # draws), so even the element that names the panel's region stays. An
      # unavailable block's panel has no heading, and its stream finds nothing
      # to update.
      #
      # Everything is read from one fresh outline, after whatever the action
      # wrote, not from the section the caller holds, which was loaded before
      # it. `editable: true` because only a request that was not denied gets
      # here. Empty when there is nothing to draw: the block named is no
      # container (the model has said so), or it was deleted while the request
      # ran.
      def section_structure_streams(section)
        outline = fresh_outline
        fresh = outline.top_level.find { |block| block.id == section.id }
        return [] unless fresh&.container?

        blocks = outline.blocks_in(fresh)
        lanes = Admin::EditorScreen::SectionLanesComponent.new(page: context.page, section: fresh, outline: outline, locale: context.locale,
          url_options: context.url_options, editable: true, holds: context.holds)
        titles = blocks.map do |inner|
          turbo_stream.update(Admin::EditorScreen::BlockCardComponent.panel_title_id(inner), Admin::EditorScreen::PanelTitleComponent.new(block: inner))
        end
        card = Admin::EditorScreen::SectionCardComponent
        [ turbo_stream.replace(card.lanes_id(fresh), lanes), *titles, words_stream(fresh), *section_count_streams(fresh, count: blocks.size) ]
      end

      # What a saved section's answer adds to the status line, the error slots
      # and the base every block's save gets. The menu and the lanes only when
      # the save changed what they show, because each is something a person
      # may be using when the answer lands: a save of the background is sent as the select
      # is left, and where the person went from it may well be the layout menu
      # or a tile.
      #
      # The layout menu, when the stored layout changed: which choice is the
      # current one, and the diagram on its button, follow what was saved. Not
      # otherwise: replaced by a save of the background, the menu's button
      # would lose the focus someone had just Shift+Tabbed onto it (to <body>,
      # since nothing was picked for `admin--editor--section` to carry the focus
      # over from), and a menu just opened by pointer would be swapped for a
      # closed one. The menu only: the hidden input the pick was written into
      # is the form's own and is left alone, as every field of a saved form is.
      #
      # The structure, when the number of columns changed. A save of the
      # background, of the width or of a layout with as many columns ("one
      # third, two thirds" for "two thirds, one third", which does change the
      # menu) moves no block, and the lanes it would redraw are tiles a person
      # may have the focus on, a menu open in or be dragging.
      #
      # The head's words, always (with the structure when it is redrawn, and
      # on their own otherwise): they say what is stored, and every saved
      # setting is one of them. A word is a button that may hold the focus
      # (`admin--editor--section#wordsTargetConnected` puts it back, and says
      # whether the settings are open). The settings region is never in an
      # answer: it is the form, which may hold text.
      #
      # Both "before"s are the section as the request loaded it, which the
      # stale-save guard has vouched for; the "after"s are read from the saved
      # record.
      def section_save_streams(section, layout_before:, columns_before:)
        streams = []
        if stored_layout(section) != layout_before
          streams << turbo_stream.replace(Admin::EditorScreen::SectionLayoutMenuComponent.dom_id(section), Admin::EditorScreen::SectionCardComponent.layout_menu(section: section))
        end
        structure = section.column_count == columns_before ? [] : section_structure_streams(section)
        streams.concat(structure.empty? ? [ words_stream(section) ] : structure)
      end

      # The section's head words (`SectionCardComponent.words`), never the
      # region they open.
      def words_stream(section)
        card = Admin::EditorScreen::SectionCardComponent
        turbo_stream.replace(card.words_id(section), card.words(section: section))
      end

      def stored_layout(block) = BlockDrawing.stored_layout(block)

      # The two counts of a section's card, after a write that changed how many
      # blocks it holds (an add into a column, a delete out of one) or how many
      # columns: the head's "3 blocks", and the number of blocks
      # its delete dialog says go with it. Counted after the write unless the
      # caller has just read the blocks, and only those two lines are replaced
      # (`SectionCardComponent.summary` and `.delete_count`, the lines the card
      # draws).
      def section_count_streams(section, count: section.section_blocks.reset.size)
        card = Admin::EditorScreen::SectionCardComponent
        [ turbo_stream.replace(card.summary_id(section), card.summary(section: section, count: count)),
          turbo_stream.replace(card.delete_count_id(section), card.delete_count(section: section, count: count)) ]
      end

      def block_card_component(block, first: false, last: false)
        Admin::EditorScreen::BlockCardComponent.new(page: context.page, block: block, locale: context.locale, url_options: context.url_options,
          first: first, last: last, holds: context.holds)
      end

      # The card of a top-level block, as the page view draws it: for a block
      # that holds blocks, a section's card (lanes, tiles and every form of the
      # blocks in it) or, on a translation tab, the group of their cards
      # (`SectionCardComponent.for`); the block's own card otherwise
      # (`SectionCardComponent.draws?` is the one rule for both, asked of the
      # outline: a section whose type is gone still holds its blocks).
      # `outline:` is for a caller that draws several cards; without it the
      # page's blocks are read once more, after whatever the action wrote.
      def card_for(block, first:, last:, outline: nil)
        outline ||= fresh_outline
        return block_card_component(block, first: first, last: last) unless Admin::EditorScreen::SectionCardComponent.draws?(block, outline: outline)

        Admin::EditorScreen::SectionCardComponent.for(page: context.page, section: block, outline: outline,
          locale: context.locale, url_options: context.url_options, first: first, last: last, holds: context.holds)
      end

      # Where a new card's stream lands: right after `after`, the card it was
      # copied from (Duplicate), or appended to the list (the "Add block" row,
      # which gives none).
      #
      # The card is rendered knowing whether it is now first and/or last (its
      # Move up / Move down start disabled accordingly). Its neighbours are not
      # re-rendered: with no between-cards pickers there is nothing else on
      # them to change, and the one thing that does (the previously-last card's
      # Move down is now enabled) is corrected in the browser by
      # `admin--editor--blocks#refreshMoveState`, which runs whenever the
      # list's children change. Re-rendering a neighbour would also throw away
      # whatever its editors held, an unsaved field included.
      def insertion_stream(block, after = nil)
        ordered = top_level_blocks.to_a
        after_block = after && ordered.find { |candidate| candidate.id == after.id }
        card = card_for(block, first: ordered.first&.id == block.id, last: ordered.last&.id == block.id)

        [ after_block ? turbo_stream.after(ActionView::RecordIdentifier.dom_id(after_block), card) : turbo_stream.append("content-blocks-list", card) ]
      end
    end
  end
end
