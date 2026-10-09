module Admin
  # Inline block editing in the page editor (cs-studio spec §5.1/§6.1,
  # Task 5): each block card is its own autosaving form (`update`), plus
  # `create` (the "Add block" row at the end of the list),
  # `destroy`, `reorder` (drag or Move up/down) and `duplicate`. Every
  # action is scoped to one page's own blocks (`set_page` + `@page.
  # content_blocks`), never a bare `ContentBlock.find` -- a block has no
  # meaning outside the page it's on, and this is what keeps one editor
  # from PATCHing a block that belongs to a page they don't have open.
  class ContentBlocksController < BaseController
    include AutosaveResponses
    include MediaFields

    # Which schema-declared settings fields and `uses_columns` a save
    # actually writes to depends on the block's own registered type (spec
    # §5.1's split rule) -- there is no fixed allowlist to hang beside
    # `Admin::PagesController`'s own `TRANSLATED_FIELDS`/`ATTRIBUTE_FIELDS`,
    # since a different block on the same page can have an entirely
    # different schema. `TRANSLATED_COLUMNS`/`ATTRIBUTE_COLUMNS` below are
    # the one thing that *is* fixed: which of the columns a type can `uses`
    # at all are translated (Mobility) versus a plain attribute -- the
    # image, whose column (`uses :image`) is saved as `media_asset_id`, the
    # id the image field's hidden input (`Admin::Columns
    # ::MediaColumnComponent`, media library Task 8) sends after a pick,
    # or "" after Remove -- `block.definition.uses_columns` still gates
    # which of these a given type's own params are actually read from.
    #
    # `TRANSLATED_COLUMNS` is derived from `ContentBlocks::Save::TRANSLATED`
    # (fix round 1) rather than a second, hand-kept `%w[caption alt body]`
    # literal -- that service is the one place a translated column actually
    # gets assigned, so this controller's own idea of "which columns are
    # translated" can never drift out of sync with it.
    TRANSLATED_COLUMNS = ContentBlocks::Save::TRANSLATED.map(&:to_s).freeze
    # `uses` column => the param (and attribute) it's sent as.
    ATTRIBUTE_COLUMNS = { "image" => "media_asset_id" }.freeze

    GONE_MESSAGE = "This block was deleted"

    before_action :set_page

    # The "Add block" row (spec §5.1): the new block is appended. `params
    # [:after_id]`, when present, is which existing block this new one goes
    # *below* -- read here, not folded into `params[:block]`, since it's this
    # controller's own insertion instruction, not a column `ContentBlocks
    # ::Save` assigns. No view sends it any more (the between-cards pickers
    # are gone; Duplicate has its own route), but it stays honoured so a
    # client that wants "insert below" has one.
    #
    # The "+" at the end of a section's lane (sections spec §4.2) posts here
    # too, with `section_id` and `column` -- read beside `params[:block]` for
    # the same reason `after_id` is. The section is looked up among this
    # page's blocks, so another page's is as gone as a deleted one: both are
    # refused before the service is asked, with the words a move into a
    # missing section gets (`ContentBlocks::Reorder::NO_COLUMN`). Everything
    # else is the service's and the model's to say (`ContentBlocks::Save`,
    # `ContentBlock#section_rules`): the block lands at the end of that
    # column, and a column the section doesn't have, or a section added into
    # a section, fails the save.
    #
    # What the answer is:
    # - the block's form and its tile (`tile_streams`), the form marked to
    #   open at once (spec §4.3), and the section's new count. Not the card:
    #   re-rendering the section would replace every other form in it, an
    #   unsaved edit included;
    # - for a refusal, the message, and the section's structure as it is now
    #   (spec §6, `section_structure_streams`). The column this tab offered
    #   may be gone because another tab gave the section fewer columns: the
    #   save under the page's lock saw the layout that tab committed, and
    #   what is drawn here is read after it -- the lanes, and with them what
    #   names a column, the headings of the forms under them and the header's
    #   count. Never a form: it is the same block's and may hold an edit. Not
    #   after a denial, which is no fault of the screen's.
    def create
      section = @page.content_blocks.find_by(id: params[:section_id]) if params[:section_id].present?
      return render(turbo_stream: picker_error_stream([ ContentBlocks::Reorder::NO_COLUMN ]), status: :unprocessable_entity) if params[:section_id].present? && section.nil?

      attributes = { block_type: params.dig(:block, :block_type) }
      attributes.merge!(section_id: section.id, section_column: params[:column]) if section
      result = ContentBlocks::Save.call(@page.content_blocks.new, attributes: attributes)

      if !result.ok?
        streams = [ picker_error_stream(result.errors) ]
        streams.concat(section_structure_streams(section)) if section && !result.denied?
        render turbo_stream: streams, status: failure_status(result)
      elsif section
        render turbo_stream: [ *tile_streams(result.record, open: true), *section_count_streams(section), *page_base_streams ], status: :created
      else
        reposition_after(result.record, params[:after_id])
        render turbo_stream: [ *insertion_stream(result.record, params[:after_id]), *page_base_streams ], status: :created
      end
    end

    # The block card's own autosave endpoint (spec §6.1) -- same shape as
    # `Admin::PagesController#update`: PATCHes on every field's `input`
    # (debounced) or `focusout`, answers with the shared Turbo Stream
    # response regardless of success. A block that no longer exists (an
    # editor's tab still open on a card another tab already deleted) 410s
    # with a fixed status message (spec §5.1's "Interfaces" list) rather
    # than raising `RecordNotFound` -- there is no per-field slot left in
    # the DOM to blame, only the status line's own wording.
    #
    # A section's settings (sections spec §4.1) are saved here too, from the
    # form in its card's header (`Admin::EditorScreen::SectionCardComponent`):
    # the same ids, the same stale-save refusal, the same error slots -- one
    # per setting, since a section's three settings are its schema's fields.
    def update
      block = @page.content_blocks.find_by(id: params[:id])
      return render_gone unless block

      # The block's own base (its `updated_at`), not the page's. A refused
      # save vouches for nothing, so it also streams no page base
      # (`page_base_streams` is only reached on success) -- see
      # `AutosaveResponses#refuse_stale_autosave`.
      return if refuse_stale_autosave(block, status_id: Admin::BlockCardComponent.error_prefix(block) + "-save-status",
        error_prefix: Admin::BlockCardComponent.error_prefix(block),
        reload_url: admin_page_path(@page, **admin_url_options))

      attributes, translations = split_block_params(block)
      stored_asset_id = block.media_asset_id
      layout_before = stored_layout(block)
      columns_before = block.column_count
      result = ContentBlocks::Save.call(block, attributes: attributes, translations: { admin_locale => translations })

      streams = autosave_stream(
        record: result.record,
        result: result,
        status_id: Admin::BlockCardComponent.error_prefix(block) + "-save-status",
        error_prefix: Admin::BlockCardComponent.error_prefix(block),
        fields: without_untouched_media_slot(block_error_fields(block), "image", sent: attributes[:media_asset_id], stored_before: stored_asset_id)
      )

      # A refused image choice puts the field back to the stored image (and
      # shows why) -- see `Admin::MediaFields`.
      refused = refused_media_field_stream(result, attribute: :media_asset_id, error_attribute: :image,
        sent: attributes[:media_asset_id]) do |stored, errors|
        Admin::BlockCardComponent.image_field(block: block, asset: stored, locale: admin_locale, errors: errors)
      end
      streams << refused if refused
      streams << tile_summary_stream(result) if block.section_id
      streams.concat(section_save_streams(result.record, layout_before: layout_before, columns_before: columns_before)) if block.container? && result.ok?
      streams.concat(page_base_streams) if result.ok?

      render turbo_stream: streams, status: autosave_status(result)
    end

    # Permanent (spec §7's "No trash" interim state) -- the card simply
    # disappears from the list, no confirmation round trip beyond the
    # `ConfirmDialogComponent` the card's own "⋯" menu already gated this
    # request behind client-side. A refusal (no `pages.edit` -- a view-only
    # editor never shows the menu, so a stale tab or a forged request) or
    # any other failure leaves the card in place and says why in the
    # page's alert slot, instead of removing a card whose block still
    # exists.
    #
    # A section has two deletes (sections spec §3.3, §4.1), and which one is
    # asked for is said beside the request, in `keep_blocks`, as `after_id`
    # and `section_id` are for an add: with it, the blocks are lifted to the
    # page's own list where the section stood ("Remove section, keep
    # blocks"); without it they go with the section, which the dialog in
    # front of that request has said, with their number. The parameter means
    # nothing for a block that holds none -- which is asked of the rows, as
    # the service asks it: a section whose type is gone is no `container?`
    # and is still emptied or lifted (`ContentBlocks::Destroy`).
    #
    # The blocks a kept section held are read before the service runs, to
    # know whose cards to draw afterwards: once lifted, nothing in a row says
    # it was in this section. A block another tab adds to the section between
    # this read and the service's lock is lifted too and gets no card from
    # this answer; it is there on the next load, as it would be for any tab
    # that was not the one adding it.
    def destroy
      block = @page.content_blocks.find_by(id: params[:id])
      return render_gone unless block

      section = block.section
      keep_blocks = params[:keep_blocks].present?
      kept_ids = keep_blocks ? block.section_blocks.ids : []
      result = ContentBlocks::Destroy.call(block, keep_blocks: keep_blocks)
      return render(turbo_stream: picker_error_stream(result.errors), status: failure_status(result)) unless result.ok?

      render turbo_stream: [ *removal_streams(block, kept_ids, section), *page_base_streams ]
    end

    # Drag reorder or Move up/down (spec §6.1): the client already knows
    # the complete new order (a drop event's own DOM order, or a client-side
    # swap before this same request) -- `ContentBlocks::Reorder` just checks
    # it names exactly this page's blocks and writes it out. Answers with
    # the status only (spec §5.1's "Interfaces" list): unlike a card's own
    # autosave, a reorder touches no field with its own error slot to
    # refresh.
    #
    # A failure also says why in the page's alert slot, and a refusal is a
    # 403 with the "no permission" status -- the order already on screen is
    # the client's optimistic one, so leaving it unexplained would look
    # saved.
    #
    # An Undo toast follows a reorder that changed something: a PATCH to this
    # same action with the order as it was, read here before the service
    # runs. The answer to *that* request (`undo=1`) also re-renders the list
    # (`update`, so the list element itself -- the Sortable container --
    # stays), since unlike a drop the client's DOM isn't already in the
    # order the server now has; and it gets a plain confirmation with no
    # Undo of its own, so two orders can't be bounced between forever.
    #
    # One container per request (sections spec §3.3): `ids` is the complete
    # new order of the page's own list or, with `section_id` and `column`,
    # of one column of one section; `moved_from[<id>][section_id]` and
    # `[column]` say where each block that comes from another container is
    # expected to be (blank for the top level). They are handed on as they
    # arrived -- ids, not attributes: the service casts every value to an
    # integer and looks each up among this page's blocks. A block that is
    # elsewhere, or a column that is gone, is a 422 with the service's
    # message, told from a denial by `result.denied?`.
    #
    # No Undo for a request that names a section or moves a block (sections
    # plan, Q5): the toast's Undo is a reorder of the page's own list back
    # to `before`, which can't put a block back into the column it left and
    # would be refused as soon as the list had gained or lost one.
    #
    # What such a request -- a STRUCTURAL one -- is answered with instead
    # (sections spec §4.4, §6):
    # - saved: each block that changed containers in its new shape
    #   (`move_streams`). The browser has moved the element already; what it
    #   cannot do is turn a card into a tile and a form under the lanes, or
    #   back;
    # - refused, and not for want of permission: the whole list as it is now
    #   (`blocks_list_stream`). The screen was behind -- the block is not
    #   where it was dragged from, the column is gone -- and how far behind
    #   is not known here, so nothing less than the list puts it right. That
    #   replaces every form on the screen, as an Undo's answer does;
    #   `admin--blocks#move` has had each send what it held first, and does
    #   not draw the list at all while a form holds text that is not saved
    #   (`#renderKeepingForms`) -- which only the browser can know, so the
    #   list is sent regardless.
    # The page's own order refused is answered as it always was, with the
    # reason alone: the browser puts its cards back, and they are still the
    # page's.
    #
    # Every parameter is read through `one_value` or `moved_from_param`: a
    # forged `section_id[]=1` is an array where an id belongs, and the
    # service casts what it is handed with `to_i`.
    def reorder
      before = top_level_blocks.ids
      section_id = one_value(params[:section_id])
      origins = moved_from_param
      structural = section_id.present? || origins.any?
      result = ContentBlocks::Reorder.call(@page, ordered_ids_param, section: section_id, column: one_value(params[:column]), moved_from: origins)
      status_id = "content-blocks-status"

      state = if result.ok? then Admin::SaveStatusComponent.new(id: status_id, state: :saved, at: Time.current)
      elsif result.denied? then Admin::SaveStatusComponent.new(id: status_id, state: :forbidden)
      else Admin::SaveStatusComponent.new(id: status_id, state: :error, count: result.errors.size)
      end

      streams = [ turbo_stream.replace(status_id, state) ]
      if result.ok?
        streams.concat(page_base_streams)
        streams.concat(structural ? move_streams(origins) : reorder_undo_streams(before))
      else
        streams << picker_error_stream(result.errors)
        streams << blocks_list_stream if structural && !result.denied?
      end
      render turbo_stream: streams, status: (result.ok? ? :ok : failure_status(result))
    end

    # Duplicate (spec §5.1; sections spec §3.3): `ContentBlocks::Duplicate`
    # makes the copy -- of a section, with every block in it -- and puts it
    # directly after its source; what is copied is said there. The copy's
    # card is inserted after the source's the same way `create`'s own
    # `after_id` does -- `after_id: source.id` here is always present,
    # unlike `create`'s (which is only sometimes given), so this never
    # falls back to appending at the end. A section's card comes with its
    # lanes, tiles and forms (`card_for`).
    #
    # The copy of a block in a column is in that column, and is drawn there
    # (`copy_tile_streams`): the page's list is not where it is.
    def duplicate
      source = @page.content_blocks.find_by(id: params[:id])
      return render_gone unless source

      result = ContentBlocks::Duplicate.call(source)
      return render(turbo_stream: picker_error_stream(result.errors), status: failure_status(result)) unless result.ok?

      copy = result.record
      streams = copy.section_id ? copy_tile_streams(copy, source) : insertion_stream(copy, source.id)
      render turbo_stream: [ *streams, *page_base_streams ], status: :created
    end

    private

    # Through the read scope (access-control design spec §3.3): blocks of a
    # page the actor can't read are a 404, whatever the action -- the page
    # isn't disclosed. Whether they may *change* the blocks of a page they
    # can read is `ContentBlocks::*`'s call (`pages.edit`, plus `publish`
    # on a published page), answered 403 below.
    def set_page
      @page = admin_scope(Page.all).find(params[:page_id])
      # Before any write this request makes touches it -- see
      # `#page_base_streams`.
      @page_updated_at_before_write = @page.updated_at
    end

    # Every successful block write touches the page (`ContentBlocks::Save`,
    # final fix wave I3), which moves the `updated_at` the page settings
    # form on this same screen holds as its autosave base -- so, left
    # alone, that form's next save would report "Changed elsewhere" against
    # nothing but this same editor's block edit.
    #
    # So a block response may move that form's base forward to the page's
    # new `updated_at` -- but only when the base the form holds (sent by
    # `admin--autosave`/`admin--blocks` as `X-Page-Base-Updated-At`) was
    # still current *before* this write (fix round 2). If the page was saved
    # elsewhere since the form loaded it (another tab, another user), the
    # sent base is older than `@page_updated_at_before_write`, and moving it
    # forward would silently absorb that save: the form's next autosave
    # would pass the staleness check and overwrite the other editor's
    # fields without a word. Then the base is left alone, so that autosave
    # still reports "Changed elsewhere". No base sent (an older client), or
    # an unparseable one, means nothing to vouch for -- left alone too.
    def page_base_streams
      return [] unless page_base_was_current?

      id = "#{Admin::PageSettingsFormComponent::ID_PREFIX}-base-updated-at"
      [ turbo_stream.replace(id, partial: "admin/shared/base_updated_at_field",
        locals: { id: id, value: Page.where(id: @page.id).pick(:updated_at).iso8601(6) }) ]
    end

    def page_base_was_current?
      sent = request.headers["X-Page-Base-Updated-At"]
      sent.present? && Time.iso8601(sent) >= @page_updated_at_before_write
    rescue ArgumentError
      false
    end

    def reorder_undo_streams(before)
      return [ blocks_list_stream, toast_stream("Order restored.") ] if params[:undo].present?

      after = top_level_blocks.ids
      return [] if after == before

      [ toast_stream("Block order changed.", kind: :undo, action: {
        label: "Undo", method: :patch,
        url: reorder_admin_page_content_blocks_path(@page, ids: before, undo: 1, **admin_url_options)
      }) ]
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
      cards = blocks.each_with_index.map { |block, index| render_to_string(card_for(block, first: index.zero?, last: index == blocks.size - 1, outline: outline)) }
      turbo_stream.update("content-blocks-list", html: helpers.safe_join(cards))
    end

    # A block in a section is a tile until it is opened, and the one line on
    # its tile is drawn from what the block holds (sections spec §4.2): every
    # answer to its autosave redraws that line, so a tile never shows the
    # caption or the image of before the save -- its form may well be closed
    # by the time the answer is here, and then the tile is all there is to
    # see. A save refused as invalid says so on the tile, for the same reason:
    # the error slots are in a form nobody may be looking at. Not a denied
    # save: that is no fault of the block's, and the error toast says it.
    #
    # Only the summary is replaced, never the tile: the tile's button may hold
    # the focus and says which form is open (`aria-expanded`). A refused stale
    # save (409) and a deleted block (410) return before this is reached; the
    # first has changed nothing and the second has no tile.
    def tile_summary_stream(result)
      turbo_stream.replace(Admin::EditorScreen::TileSummaryComponent.dom_id(result.record),
        Admin::EditorScreen::TileSummaryComponent.new(block: result.record, locale: admin_locale, invalid: !result.ok? && !result.denied?))
    end

    # A block in a section is two elements (sections spec §4.3): its tile,
    # which has the block's `dom_id` and is what `destroy` removes like a
    # card, and its form's panel under the lanes. The panel goes with it --
    # and it can be the very thing on screen: an unavailable block's panel
    # has "Delete block…" in it. Left behind it would stay open with no tile
    # to close it from, its Delete answering 410. `admin--section` needs no
    # telling: the open form is whichever panel is showing, and none is.
    def panel_removal_streams(block)
      block.section_id ? [ turbo_stream.remove(Admin::BlockCardComponent.panel_id(block)) ] : []
    end

    # A block's two halves inside a section, in the order `admin--section`
    # needs them: the panel (its form) first, then the tile that opens it.
    # Either order would open the form -- whichever target connects second
    # finds the other (`openIfNew`) -- but with the form already there the
    # tile is never on screen with nothing to open.
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
    # the source's -- where `ContentBlocks::Duplicate` put it, which is not
    # the end of the lane `tile_streams` appends to -- and the section's two
    # counts, which a copy raises as an add does.
    #
    # NOT OPENED, unlike a block just added (sections spec §4.3, "a block
    # just added opens at once"): an added block is empty and its form is what
    # the person came for; a copy already holds what its source holds, and
    # what follows a Duplicate is as often moving the copy as editing it.
    # Opening it would also close the form that is open in the section, which
    # may be the source's, mid-edit. The focus goes to the copy's menu
    # (`admin--blocks#focusCopy`), from where it is opened, moved or copied on.
    def copy_tile_streams(copy, source)
      section = copy.section
      [ turbo_stream.append(Admin::EditorScreen::SectionCardComponent.panels_id(section), panel_component(copy)),
        turbo_stream.after(ActionView::RecordIdentifier.dom_id(source), tile_component(copy)),
        *section_count_streams(section) ]
    end

    def panel_component(block, open: false)
      Admin::BlockCardComponent.new(page: @page, block: block, locale: admin_locale, url_options: admin_url_options, editable: true, placement: :panel, open: open)
    end

    def tile_component(block, open: false)
      Admin::EditorScreen::BlockTileComponent.new(page: @page, block: block, locale: admin_locale, url_options: admin_url_options, editable: true, open: open)
    end

    # Each block a saved reorder moved between containers, in its new shape
    # (sections spec §4.4; plan D8), and the count of every section that
    # gained or lost one. `origins` is the request's `moved_from`, which the
    # service has just found true: where each block was.
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
    # THE BROWSER HAS ALREADY MOVED THE ELEMENT (`admin--blocks#move`), so the
    # `replace` of the block's `dom_id` lands where it was dropped, and
    # nothing here says a position.
    #
    # THE ONE PLACE A FORM IS REPLACED BY A MOVE. Everything else that redraws
    # part of a section leaves its panels alone (`section_structure_streams`),
    # because a form holds what is typed and its place in the write queue. A
    # form can't be kept here: a card's is inside the card, a panel's is under
    # the lanes of the section it left. So the browser sends what the form
    # holds before the move, and doesn't send the move at all for a form that
    # did not end clean; the forms drawn here are new ones, with the block's
    # base as it is now -- which a move leaves alone
    # (`ContentBlocks::Reorder` writes with `update_columns`).
    #
    # The old panel is removed first in every case but the last: for a card
    # the stream finds none, and a panel appended before the old one left
    # would be the second element with its id.
    def move_streams(origins)
      outline = fresh_outline
      # Every top-level block by id, not only the containers: a block moved
      # out of a section whose type is gone left a card that still counts
      # its blocks, in its delete dialog (spec §6).
      sections = outline.top_level.index_by(&:id)
      top_level = outline.top_level
      touched = []

      streams = outline.reading_order.select { |block| origins.key?(block.id.to_s) }.flat_map do |block|
        from = origins.dig(block.id.to_s, "section_id").presence&.to_i
        touched.push(from, block.section_id)
        dom = ActionView::RecordIdentifier.dom_id(block)
        old_panel = turbo_stream.remove(Admin::BlockCardComponent.panel_id(block))

        if from == block.section_id
          [ turbo_stream.update(Admin::BlockCardComponent.panel_title_id(block), Admin::EditorScreen::PanelTitleComponent.new(block: block)) ]
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
    # with its panel, and its section recounted; or a section's card --
    # replaced, when its blocks were kept, by their cards in the order they
    # now have at the top level, which is the reading order they had in it
    # (`ContentBlocks::Destroy#lift`).
    #
    # The cards are a block list's own (`card_for`): each a new form with the
    # block's base as it is now, registered with the write queue as it
    # connects. The forms they replace -- the section's panels -- go with the
    # section's card; an edit one of them held inside its debounce was sent
    # before the delete (the menu's press took the focus off the field, and
    # the delete waits its turn in the queue behind that save). Each card is
    # told whether it is the list's first or last, as on a page load; its
    # neighbours are corrected in the browser (`admin--blocks
    # #refreshMoveState`, on every change of the list's children).
    def removal_streams(block, kept_ids, section)
      id = ActionView::RecordIdentifier.dom_id(block)
      return [ turbo_stream.remove(id), *panel_removal_streams(block), *section_count_streams(section) ] if section
      return [ turbo_stream.remove(id) ] if kept_ids.empty?

      ordered = top_level_blocks.to_a
      cards = ordered.select { |lifted| kept_ids.include?(lifted.id) }.map do |lifted|
        render_to_string(card_for(lifted, first: ordered.first == lifted, last: ordered.last == lifted))
      end
      [ turbo_stream.replace(id, html: helpers.safe_join(cards)) ]
    end

    # A section's structure as the database has it now, for an answer that
    # must put right what this tab shows of it (sections spec §3.3, §6): a
    # save of the section that changed how many columns it has -- a narrower
    # layout folds the blocks of the removed columns into the last one left
    # (`ContentBlocks::Save#fold_removed_columns`) -- and an add refused
    # because another tab removed the column it named.
    #
    # THE ONE REDRAW OF A SECTION'S LANES. Three things on screen say which
    # column a block is in, and they are brought up to date together or the
    # screen contradicts itself: the lanes with their tiles; the heading of
    # each block's form under them ("Image · column 2"), whether it is open
    # or not; and the header's count of columns and blocks, with the delete
    # dialog's. So nothing draws the lanes alone.
    #
    # NEVER A PANEL. A block's form is in the page from the start and stays
    # (`Admin::EditorScreen::SectionCardComponent`): it may hold text that is
    # not saved, and it is registered with the write queue as the element it
    # is. The heading's text is rewritten inside the heading (`update`, with
    # `Admin::EditorScreen::PanelTitleComponent`, the words the panel itself
    # draws), so even the element that names the panel's region stays. An unavailable
    # block's panel has no heading, and its stream finds nothing to update.
    #
    # Everything is read from one fresh outline, after whatever the action
    # wrote -- not from the section the caller holds, which was loaded before
    # it. `editable: true` because only a request that was not denied gets
    # here. Empty when there is nothing to draw: the block named is no
    # container (the model has said so), or it was deleted while the request
    # ran.
    def section_structure_streams(section)
      outline = fresh_outline
      fresh = outline.top_level.find { |block| block.id == section.id }
      return [] unless fresh&.container?

      blocks = outline.blocks_in(fresh)
      lanes = Admin::EditorScreen::SectionLanesComponent.new(page: @page, section: fresh, outline: outline, locale: admin_locale, url_options: admin_url_options, editable: true)
      titles = blocks.map do |inner|
        turbo_stream.update(Admin::BlockCardComponent.panel_title_id(inner), Admin::EditorScreen::PanelTitleComponent.new(block: inner))
      end
      [ turbo_stream.replace(Admin::EditorScreen::SectionCardComponent.lanes_id(fresh), lanes), *titles, *section_count_streams(fresh, count: blocks.size) ]
    end

    # What a saved section's answer adds to the status line, the error slots
    # and the base every block's save gets (`update`). Each part only when
    # the save changed what it shows, because each is something a person may
    # be using when the answer lands: a save of the background is sent as the
    # select is left, and where the person went from it may well be the
    # layout menu or a tile.
    #
    # The layout menu, when the stored layout changed: which choice is the
    # current one, and the diagram on its button, follow what was saved. Not
    # otherwise (fix round 1 of the section's controls): replaced by a save
    # of the background, the menu's button lost the focus someone had just
    # Shift+Tabbed onto it -- to <body>, since nothing was picked for
    # `admin--section` to carry the focus over from -- and a menu just opened
    # by pointer was swapped for a closed one. The menu only -- the hidden
    # input the pick was written into is the form's own and is left alone,
    # as every field of a saved form is.
    #
    # The structure, when the number of columns changed. A save of the
    # background, of the width or of a layout with as many columns ("one
    # third, two thirds" for "two thirds, one third", which does change the
    # menu) moves no block, and the lanes it would redraw are tiles a person
    # may have the focus on, a menu open in or be dragging.
    #
    # Both "before"s are the section as this request loaded it, which the
    # stale-save guard has just vouched for; the "after"s are read from the
    # saved record.
    def section_save_streams(section, layout_before:, columns_before:)
      streams = []
      if stored_layout(section) != layout_before
        streams << turbo_stream.replace(Admin::EditorScreen::SectionLayoutMenuComponent.dom_id(section), Admin::EditorScreen::SectionCardComponent.layout_menu(section: section))
      end
      streams.concat(section_structure_streams(section)) if section.column_count != columns_before
      streams
    end

    # A section's layout as its type reads it -- the schema's default where
    # the row stores none, as a section just made does, so that section's
    # first save of a background is no change of layout. Nil for a block
    # that has none.
    def stored_layout(block) = block.container? ? block.settings_object(locale: ::Locales.default)&.layout : nil

    # The two counts of a section's card, after a write that changed how many
    # blocks it holds (an add into a column, a delete out of one) or how many
    # columns: the header's "2 columns · 3 blocks", and the number of blocks
    # its delete dialog says go with it. Counted after the write unless the
    # caller has just read the blocks, and only those two lines are replaced
    # (`SectionCardComponent.summary` and `.delete_count`, the lines the card
    # draws).
    def section_count_streams(section, count: section.section_blocks.reset.size)
      card = Admin::EditorScreen::SectionCardComponent
      [ turbo_stream.replace(card.summary_id(section), card.summary(section: section, count: count)),
        turbo_stream.replace(card.delete_count_id(section), card.delete_count(section: section, count: count)) ]
    end

    # The page's own list (sections spec §3.1): the blocks outside any
    # section, which is what the block list shows as cards, what "first" and
    # "last" are counted among and what a reorder of the page names. A block
    # in a section's column has its `position` counted in that column, so it
    # is no part of this order. A fresh query each time it is asked -- every
    # caller reads it after a service has written.
    def top_level_blocks = @page.content_blocks.top_level.reorder(:position, :id)

    # `moved_from` as a plain hash of hashes, or none: a request may leave it
    # out, and a forged one may send anything where the hash belongs, where
    # an entry's does, or where one of its two ids does (`one_value`). An
    # entry that is no hash names no place, which is what the service reads
    # as "the top level" -- and what `move_streams` reads from the same hash.
    def moved_from_param
      moved = params[:moved_from]
      return {} unless moved.respond_to?(:to_unsafe_h)

      moved.to_unsafe_h.transform_values { |from| from.is_a?(Hash) ? from.transform_values { |value| one_value(value) } : {} }
    end

    # The new order as the service takes it: a list of ids. Anything else
    # where the list belongs is no order at all, and an entry that is not one
    # value names no block -- which the service then refuses.
    def ordered_ids_param = (params[:ids].is_a?(Array) ? params[:ids] : []).map { |id| one_value(id) }

    # A parameter that is to be one id or number: an array or a hash in its
    # place (`section_id[]=1`, `column[a]=1`) is read as not sent.
    def one_value(value) = value.is_a?(String) || value.is_a?(Numeric) ? value : nil

    def failure_status(result) = result.denied? ? :forbidden : :unprocessable_entity

    def block_card_component(block, first: false, last: false)
      Admin::BlockCardComponent.new(page: @page, block: block, locale: admin_locale, url_options: admin_url_options, first: first, last: last)
    end

    # The card of a top-level block, as the page view draws it: for a block
    # that holds blocks, a section's card -- lanes, tiles and every form of
    # the blocks in it -- or, on a translation tab, the group of their cards
    # (`SectionCardComponent.for`); the block's own card otherwise
    # (`SectionCardComponent.draws?` is the one rule for both, asked of the
    # outline: a section whose type is gone still holds its blocks).
    # `outline:` is for a caller that draws several cards; without it the
    # page's blocks are read once more, after whatever the action wrote.
    def card_for(block, first:, last:, outline: nil)
      outline ||= fresh_outline
      return block_card_component(block, first: first, last: last) unless Admin::EditorScreen::SectionCardComponent.draws?(block, outline: outline)

      Admin::EditorScreen::SectionCardComponent.for(page: @page, section: block, outline: outline,
        locale: admin_locale, url_options: admin_url_options, first: first, last: last)
    end

    # The page's blocks as they are now: `reset` drops what the association
    # loaded before the action's service wrote.
    def fresh_outline = BlockOutline.new(@page.content_blocks.reset)

    # Splits `params[:block]` by the exact rule spec §5.1 lays out: schema
    # fields with `translated?` go to `translations[locale][:settings]`,
    # the rest to `attributes[:settings]`; `caption`/`alt`/`body` are
    # translated columns (`body` the rich-text document JSON), `image` is a
    # plain attribute (`media_asset_id`) -- every one of
    # those gated by whether this block's own type actually `uses` that
    # column at all, the same allowlist reasoning
    # `Admin::PagesController::ATTRIBUTE_FIELDS` uses for its own record.
    def split_block_params(block)
      block_params = params.fetch(:block, ActionController::Parameters.new)
      definition = block.definition

      attributes = {}
      translations = {}

      if definition && (block_params.key?(:settings) || block_params[:groups_present].present?)
        settings = block_params.key?(:settings) ? block_params[:settings].to_unsafe_h : {}
        apply_missing_groups(settings, definition, block_params[:groups_present])
        normalize_group_fields(settings, definition)

        plain, translated = split_settings(settings, definition)
        attributes[:settings] = plain
        translations[:settings] = translated
      end

      uses = definition&.uses_columns || []
      TRANSLATED_COLUMNS.each { |column| translations[column.to_sym] = block_params[column] if uses.include?(column) && block_params.key?(column) }
      ATTRIBUTE_COLUMNS.each { |column, param| attributes[param.to_sym] = block_params[param] if uses.include?(column) && block_params.key?(param) }

      [ attributes, translations ]
    end

    # A `groups` field's raw params need straightening into an ordered
    # Array before `ContentBlock#assign_settings` ever sees them -- see
    # `Admin::FieldParams`'s own comment. No built-in block type declares
    # one yet, so this is a no-op today; it's here so the first one that
    # does gets it for free.
    def normalize_group_fields(settings, definition)
      definition.fields.select { |field| field.type == :groups }.each do |field|
        key = field.name
        settings[key] = Admin::FieldParams.normalize(settings[key]) if settings.key?(key)
      end
    end

    # A `groups` field with every row removed sends no key of its own at all
    # -- there's nothing left to name (finding 2, final-fixes round) -- which
    # would otherwise read identically to "this form never touched this
    # field," leaving whatever was last saved untouched instead of emptied.
    # `Admin::Fields::GroupsField`'s own hidden `groups_present` marker
    # (rendered once per groups field, regardless of row count) is what
    # tells the two apart: every name listed there is a groups field this
    # form *did* render, so a missing key for it means "saved as empty," not
    # "not part of this request." Mirrors `Admin::PostsController`'s own
    # `apply_missing_groups` exactly; duplicated rather than shared for the
    # same reason `normalize_group_fields` already is on both controllers
    # (see that method's own comment on `Admin::PostsController`).
    def apply_missing_groups(hash, definition, groups_present)
      present = Array(groups_present).map(&:to_s)

      definition.fields.select { |field| field.type == :groups && present.include?(field.name) }.each do |field|
        hash[field.name] = [] unless hash.key?(field.name)
      end
    end

    def split_settings(settings, definition)
      plain, translated = {}, {}

      definition.fields.each do |field|
        next unless settings.key?(field.name)

        (field.translated? ? translated : plain)[field.name] = settings[field.name]
      end

      [ plain, translated ]
    end

    # `fields:` for `Admin::AutosaveResponses#autosave_stream` -- every
    # schema field's error lives under the dotted `"settings.<name>"` key
    # `ContentBlock#settings_are_valid` reports it against (its own
    # comment explains why); every `uses_columns` entry reports directly
    # under its own bare name, same as `Admin::PagesController`'s own
    # column fields.
    def block_error_fields(block)
      definition = block.definition
      return {} unless definition

      fields = definition.fields.each_with_object({}) { |field, hash| hash[field.name] = [ "settings.#{field.name}" ] }
      definition.uses_columns.each_with_object(fields) { |column, hash| hash[column] = [ column ] }
    end

    # Appends `block.id` right after `after_id` in the page's current block
    # order, then persists that through `ContentBlocks::Reorder` -- shared
    # by `create`'s "add between two cards" and `duplicate`'s "insert right
    # after the source". A blank `after_id` (the end-of-list picker, or a
    # `create` with none given) leaves the block exactly where
    # `ContentBlocks::Save#assign_position` already appended it, so there's
    # nothing here to do.
    def reposition_after(block, after_id)
      return if after_id.blank?

      ordered = top_level_blocks.ids
      ordered.delete(block.id)
      index = ordered.index(after_id.to_i)
      ordered.insert(index ? index + 1 : ordered.length, block.id) # version: none (Array#insert, no SQL)
      ContentBlocks::Reorder.call(@page, ordered)
    end

    # Where the new card's own Turbo Stream lands: right after the card it
    # was added below (an `after_id`, which Duplicate always has), or appended
    # to the list (the "Add block" row, or a stale/blank `after_id`).
    #
    # The card is rendered knowing whether it is now first and/or last (its
    # Move up / Move down start disabled accordingly). Its neighbours are not
    # re-rendered: with no between-cards pickers there is nothing else on them
    # to change, and the one thing that does -- the previously-last card's
    # Move down is now enabled -- is corrected in the browser by `admin
    # --blocks#refreshMoveState`, which runs whenever the list's children
    # change. (Re-rendering a neighbour would also throw away whatever its
    # editors held, an unsaved field included.)
    def insertion_stream(block, after_id)
      ordered = top_level_blocks.to_a
      after_block = after_id.present? ? ordered.find { |candidate| candidate.id == after_id.to_i } : nil
      card = card_for(block, first: ordered.first&.id == block.id, last: ordered.last&.id == block.id)

      [ after_block ? turbo_stream.after(ActionView::RecordIdentifier.dom_id(after_block), card) : turbo_stream.append("content-blocks-list", card) ]
    end

    def picker_error_stream(errors)
      turbo_stream.replace("content-blocks-alert", partial: "admin/shared/field_errors", locals: { id: "content-blocks-alert", messages: errors })
    end

    # The Turbo Stream `update`/`destroy`/`duplicate` answer with for a
    # block that's already gone (spec §5.1's "Interfaces" list: "A PATCH to
    # a destroyed block answers 410 with the status 'This block was
    # deleted'") -- there's no card left in the DOM to replace a save-status
    # line inside of, so this targets a fixed id every page editor renders
    # once, up front (`content-blocks-alert`), the same slot a failed
    # `create` also reports into.
    def render_gone
      render turbo_stream: turbo_stream.replace("content-blocks-alert",
        partial: "admin/shared/field_errors", locals: { id: "content-blocks-alert", messages: [ GONE_MESSAGE ] }), status: :gone
    end
  end
end
