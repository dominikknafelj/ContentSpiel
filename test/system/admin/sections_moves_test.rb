require "application_system_test_case"

class Admin::SectionsMovesSystemTest < Admin::SectionsSystemTestCase
  # ---- Moving by drag (sections spec §4.4; plan D8, D9) ----
  #
  # A drop is driven the way `blocks_test.rb`'s "dragging a block's handle
  # reorders the list" drives it: the element is moved in the DOM as a drop
  # leaves it, then the controller's own sender is called, which is the code a
  # drop's `onEnd` runs. That makes a test independent of how fast SortableJS
  # samples the pointer; the tests named "the pointer ..." use the pointer for
  # real, and are what holds the Sortables' own wiring (handle, group, `put`).

  test "a tile dropped in another lane is saved there and its form says the new column" do
    open_editor
    drop_into(@left, lane(2))

    assert_eventually { @left.reload.section_column == 2 }
    assert_equal [ @right.id, @left.id ], @page.content_blocks.in_column(@section, 2).reorder(:position).ids
    find(face(@left)).click
    assert_selector panel(@left), text: "Image · column 2"
  end

  # Plan D8: a move inside one section moves the element only. The form under
  # the lanes is the element it was, with what was typed into it and its place
  # in the write queue.
  test "a tile that changes lanes keeps its open form, the element itself, and what is typed in it" do
    open_editor
    find(face(@left)).click
    page.execute_script("document.querySelector(#{panel(@left).to_json}).__same = true")
    fill_in id: caption(@left), with: "Typed, then moved across"

    drop_into(@left, lane(2))

    assert_selector panel(@left), text: "Image · column 2"
    assert_writes_settled
    assert_equal true, page.evaluate_script("document.querySelector(#{panel(@left).to_json}).__same")
    assert_field caption(@left), with: "Typed, then moved across"
    assert_selector "#{face(@left)}[aria-expanded='true']"
    assert_equal [ 2, "Typed, then moved across" ], @left.reload.then { |block| [ block.section_column, block.caption ] }
    assert_selector "#section-#{@section.id}-summary", text: "2 blocks"
  end

  test "a tile moved within its lane is saved in its new place, with no Undo offered" do
    third = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 1)
    open_editor

    drop_into(@left, lane(1))

    assert_eventually { @page.content_blocks.in_column(@section, 1).reorder(:position).ids == [ third.id, @left.id ] }
    assert_writes_settled
    assert_equal [ third.id, @left.id ], tiles_in(1)
    assert_selector "#content-blocks-status", text: "SAVED"
    assert_no_selector "#toasts .admin-toast"
  end

  test "a tile dropped in the page's list becomes a card with its form, and the section recounts" do
    open_editor
    drop_into(@left, "#content-blocks-list")

    assert_selector "#content-blocks-list > .admin-block-card[data-block-id='#{@left.id}'] form[data-controller~='admin--saving--autosave']"
    assert_no_selector panel(@left), visible: :all
    assert_selector "#section-#{@section.id}-summary", text: "1 block"
    assert_nil @left.reload.section_id
    assert_equal [ @section.id, @left.id ], @page.content_blocks.top_level.reorder(:position).ids

    # The card is the list's own: it saves, and its menu moves it.
    fill_in id: caption(@left), with: "Typed into the card"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "SAVED"
    assert_equal "Typed into the card", @left.reload.caption
    assert_selector "#{tile(@left)} button[data-move='down'][disabled]", visible: :all
    assert_no_selector "#{tile(@left)} button[data-move='up'][disabled]", visible: :all
  end

  test "a card dropped in a lane becomes a tile there, and its form opens from the tile and saves" do
    card = @page.content_blocks.create!(block_type: "image", position: 1)
    open_editor
    drop_into(card, lane(1))

    assert_selector "#{lane(1)} > .admin-block-tile[data-block-id='#{card.id}']"
    assert_selector "#block-#{card.id}-panel", visible: :all
    assert_no_selector "#block-#{card.id}-panel"
    assert_equal [ @section.id, 1, 1 ], card.reload.then { |b| [ b.section_id, b.section_column, b.position ] }
    assert_selector "#section-#{@section.id}-summary", text: "3 blocks"
    assert_selector "#content-blocks-list > [data-block-id]", count: 1

    find(face(card)).click
    assert_selector "#block-#{card.id}-panel", text: "Image · column 1"
    fill_in id: caption(card), with: "Typed into the panel"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{card.id}-save-status", text: "SAVED"
    assert_equal "Typed into the panel", card.reload.caption
  end

  # A text block's form is an editor that boots again each time its card is
  # moved in the DOM. Whatever it writes into its field as it does must not
  # read as an edit nobody saved, or no text could ever be moved.
  test "a text card and a text tile are moved between the list and a lane with their words, and nothing is saved over them" do
    text = @page.content_blocks.create!(block_type: "rich_text", position: 1, body: rich_doc("Words that travel"))
    stamp = text.updated_at
    open_editor
    assert_selector "#{tile(text)} .ProseMirror", text: "Words that travel"

    drop_into(text, lane(2))

    assert_selector "#{lane(2)} > .admin-block-tile[data-block-id='#{text.id}']", text: "Words that travel"
    assert_no_selector "#toasts .admin-toast"
    find(face(text)).click
    assert_selector "#{panel(text)} .ProseMirror", text: "Words that travel"

    drop_into(text, "#content-blocks-list")

    assert_selector "#content-blocks-list > .admin-block-card[data-block-id='#{text.id}'] .ProseMirror", text: "Words that travel"
    assert_no_selector "#toasts .admin-toast"
    assert_writes_settled
    assert_nil text.reload.section_id
    assert_equal stamp, text.updated_at, "a move saved the block's form"
  end

  test "a tile dropped in another section takes its form there" do
    other = @page.content_blocks.create!(block_type: "section", position: 1)
    open_editor
    find(face(@left)).click

    drop_into(@left, lane(1, other))

    assert_selector "#section-#{other.id}-panels > #{panel(@left)}", visible: :all
    assert_no_selector "#section-#{@section.id}-panels > #{panel(@left)}", visible: :all
    assert_selector "#{lane(1, other)} > .admin-block-tile[data-block-id='#{@left.id}']"
    assert_selector "#section-#{@section.id}-summary", text: "1 block"
    assert_selector "#section-#{other.id}-summary", text: "1 block"
    assert_equal [ other.id, 1 ], @left.reload.then { |b| [ b.section_id, b.section_column ] }

    find(face(@left)).click
    assert_selector panel(@left), text: "Image · column 1"
    fill_in id: caption(@left), with: "In the other section"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "SAVED"
    assert_equal "In the other section", @left.reload.caption
  end

  # Review Focus 4.
  test "an edit still inside its debounce is saved before its block is moved out of the section" do
    open_editor
    find(face(@left)).click
    page.execute_script(<<~JS)
      const field = document.getElementById(#{caption(@left).to_json})
      field.value = "Typed, then dragged out"
      field.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    drop_into(@left, "#content-blocks-list")

    assert_selector "#content-blocks-list > .admin-block-card[data-block-id='#{@left.id}']"
    assert_writes_settled
    assert_equal "Typed, then dragged out", @left.reload.caption
    assert_field caption(@left), with: "Typed, then dragged out"
    assert_no_text "CHANGED ELSEWHERE"
  end

  # Review Focus 4. The block's own save is on the wire when more is typed and
  # the tile is dropped: what was typed last is sent by that save's follow-up,
  # which is queued BEHIND the move. A move sent in its turn would have its
  # answer draw the form without those words, on a base the follow-up then
  # makes stale. So the move stands back once and goes after it.
  test "an edit typed while the block's save is on the wire is saved before the block is moved out" do
    open_editor
    find(face(@left)).click
    script_writes("hold")
    fill_in id: caption(@left), with: "First, on the wire"
    page.execute_script("document.activeElement.blur()")
    await_js "typeof window.__release[0] === 'function'"
    page.execute_script(<<~JS)
      const field = document.getElementById(#{caption(@left).to_json})
      field.value = "Second, typed behind it"
      field.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    drop_into(@left, "#content-blocks-list")
    page.execute_script("window.__release[0]()")

    assert_selector "#content-blocks-list > .admin-block-card[data-block-id='#{@left.id}']"
    assert_writes_settled
    assert_equal "Second, typed behind it", @left.reload.caption
    assert_field caption(@left), with: "Second, typed behind it"
    assert_equal 3, page.evaluate_script("window.__writes.length"), "the two saves and the move"
    assert_match %r{/reorder}, page.evaluate_script("window.__writes[2]"), "the move went before the save it had to wait for"

    # The card's form holds the block's base as that last save left it.
    fill_in id: caption(@left), with: "Third, in the card"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "SAVED"
    assert_writes_settled
    assert_equal "Third, in the card", @left.reload.caption
    assert_no_text "CHANGED ELSEWHERE"
  end

  # Review Focus 4.
  test "a block whose form was refused stays where it is, with its text, and a toast says why" do
    open_editor
    find(face(@left)).click
    travel 1.minute do
      as_unheard(users(:two)) { ContentBlocks::Save.call(@left, translations: { "en" => { caption: "Theirs" } }) }
    end
    fill_in id: caption(@left), with: "Mine, refused"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE", wait: 8
    count_writes

    drop_into(@left, "#content-blocks-list")

    assert_selector "#toasts .admin-toast[role=alert]", text: "Reload or fix this block before moving it"
    assert_selector "#{lane(1)} > .admin-block-tile[data-block-id='#{@left.id}']"
    assert_no_selector "#content-blocks-list > [data-block-id='#{@left.id}']"
    assert_field caption(@left), with: "Mine, refused"
    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE"
    assert_equal @section.id, @left.reload.section_id
    assert_equal "Theirs", @left.caption
    await_frames # a move that went out after all would have called fetch by now: its turn in the queue came before the toast
    assert_equal [], page.evaluate_script("window.__writes"), "the move was sent"

    # Dropping it again replaces the toast, never stacks it.
    drop_into(@left, lane(2))
    assert_order_eventually([ @left.id ]) { tiles_in(1) }
    assert_selector "#toasts .admin-toast", text: "Reload or fix this block before moving it", count: 1
  end

  # Review Focus 4. A save that is waiting out a retry is not one the move can
  # go behind: nothing of it is in the queue. The move stands back once, finds
  # the form no further, and is given up -- the words are still only here.
  test "a block whose save is still being retried is not moved, and keeps its text" do
    open_editor
    find(face(@left)).click
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__writes = []
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() === "GET") return originalFetch(url, options)
        if (String(url.url || url).includes("/cs-studio/editing/")) return originalFetch(url, options) // a claim is not the save this test fails
        window.__writes.push(String(url.url || url))
        return /reorder/.test(String(url.url || url)) ? originalFetch(url, options) : Promise.reject(new TypeError("Failed to fetch"))
      }
    JS
    fill_in id: caption(@left), with: "Typed while offline"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: /RETRYING/i

    drop_into(@left, "#content-blocks-list")

    assert_selector "#toasts .admin-toast[role=alert]", text: "Reload or fix this block before moving it"
    assert_order_eventually([ @left.id ]) { tiles_in(1) }
    assert_field caption(@left), with: "Typed while offline"
    assert_equal @section.id, @left.reload.section_id
    assert_empty page.evaluate_script("window.__writes").grep(/reorder/), "the move was sent"
    assert_equal [ "/cs-studio/pages/#{@page.id}/content_blocks/#{@left.id}" ], page.evaluate_script("window.__writes").map { |url| URI.parse(url).path }.uniq, "only the block's own save was failed"
  end

  # Review Focus 4, for a card: its form is in the card, and it is the same rule.
  test "a card whose save was refused as invalid is not moved into a lane" do
    card = @page.content_blocks.create!(block_type: "post_list", position: 1)
    open_editor
    fill_in id: "block-#{card.id}-limit", with: "0"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{card.id}-save-status", text: /COULDN.T SAVE/i

    drop_into(card, lane(1))

    assert_selector "#toasts .admin-toast[role=alert]", text: "Reload or fix this block before moving it"
    assert_order_eventually([ @section.id, card.id ]) { cards_in_list }
    assert_equal [ @left.id ], tiles_in(1)
    assert_field "block-#{card.id}-limit", with: "0"
    assert_nil card.reload.section_id
  end

  # Review Focus 5.
  test "a drop into a column another tab has folded away is refused and the list is redrawn" do
    card = @page.content_blocks.create!(block_type: "image", position: 1)
    open_editor
    as_unheard(users(:two)) { assert ContentBlocks::Save.call(ContentBlock.find(@section.id), attributes: { settings: { "layout" => "one" } }).ok? }
    # An edit in another block's form, still inside its debounce: the list
    # that the refusal brings replaces that form.
    page.execute_script(<<~JS)
      const field = document.getElementById(#{caption(card).to_json})
      field.value = "Typed in a card, not sent yet"
      field.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    drop_into(@left, lane(2))

    assert_selector "#content-blocks-alert", text: "That section or column no longer exists"
    assert_selector "#section-#{@section.id}-lanes [data-admin--editor--blocks-target='lane']", count: 1
    assert_selector "#{lane(1)} > .admin-block-tile", count: 2
    assert_selector "#content-blocks-status", text: /COULDN.T SAVE/i
    assert_writes_settled
    assert_equal [ [ 1, 0 ], [ 1, 1 ] ], [ @left, @right ].map { |block| block.reload.then { |b| [ b.section_column, b.position ] } }
    assert_empty @page.content_blocks.where(section_id: @section.id).where.not(section_column: 1)
    assert_equal "Typed in a card, not sent yet", card.reload.caption
    assert_field caption(card), with: "Typed in a card, not sent yet"

    # The lanes that came are lanes like any: a tile is dropped out of one.
    drop_into(@right, "#content-blocks-list")
    assert_selector "#content-blocks-list > .admin-block-card[data-block-id='#{@right.id}']"
    assert_nil @right.reload.section_id
  end

  RELOAD_LATER = "Something on this page changed elsewhere. Reload once your unsaved text is safe.".freeze

  # A refusal's list replaces every form on the screen, and a
  # form paused by a 409 holds the only copy of what was typed -- which its
  # bar has promised stays. A 409 and a refused move have one cause, a second
  # editor on the page, so the two meet. Then the list is NOT drawn: the block
  # goes back, the reason is said with a line about reloading, and nothing
  # else on the screen changes.
  test "a refused move does not redraw the list while another block's form holds text that was refused" do
    open_editor
    find(face(@right)).click
    travel 1.minute do
      as_unheard(users(:two)) { ContentBlocks::Save.call(@right, translations: { "en" => { caption: "Theirs" } }) }
    end
    fill_in id: caption(@right), with: "Mine, refused"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@right.id}-save-status", text: "CHANGED ELSEWHERE", wait: 8
    page.execute_script("document.querySelector(#{tile(@section).to_json}).__same = true")
    # Moved behind this screen's back: the drop says it comes from column 1.
    ContentBlock.where(id: @left.id).update_all(section_column: 2, position: 1) # version: none (a test's own stale screen)

    drop_into(@left, "#content-blocks-list")

    assert_selector "#content-blocks-alert", text: ContentBlocks::Reorder::STALE
    assert_selector "#content-blocks-alert", text: RELOAD_LATER
    assert_order_eventually([ @left.id ]) { tiles_in(1) }
    assert_equal [ @section.id ], cards_in_list
    await_frames # a list drawn after all would be in the page by now: Turbo draws a stream on the next frame
    assert_equal true, page.evaluate_script("document.querySelector(#{tile(@section).to_json}).__same"), "the list was redrawn"
    assert_field caption(@right), with: "Mine, refused"
    assert_selector "#block-#{@right.id}-save-status", text: "CHANGED ELSEWHERE"
    assert_equal "Theirs", @right.reload.caption
    assert_equal false, page.evaluate_script("document.querySelector(#{tile(@left).to_json}).inert")
  end

  # The same for text typed into another form while the move was on the wire:
  # what counts is what the forms hold when the answer arrives.
  test "a refused move does not redraw the list over text typed while its request was out, and that text is then saved" do
    open_editor
    find(face(@right)).click
    ContentBlock.where(id: @left.id).update_all(section_column: 2, position: 1) # version: none (a test's own stale screen)
    script_writes("hold")

    drop_into(@left, "#content-blocks-list")
    await_js "typeof window.__release[0] === 'function'"
    page.execute_script("document.querySelector(#{tile(@section).to_json}).__same = true")
    fill_in id: caption(@right), with: "Typed while the move was out"
    page.execute_script("window.__release[0]()")

    assert_selector "#content-blocks-alert", text: ContentBlocks::Reorder::STALE
    assert_selector "#content-blocks-alert", text: RELOAD_LATER
    assert_order_eventually([ @left.id ]) { tiles_in(1) }
    page.execute_script("document.activeElement.blur()")
    assert_writes_settled
    assert_equal true, page.evaluate_script("document.querySelector(#{tile(@section).to_json}).__same"), "the list was redrawn"
    assert_field caption(@right), with: "Typed while the move was out"
    assert_equal "Typed while the move was out", @right.reload.caption
  end

  # A block whose move between containers is on the wire is
  # about to be replaced by its answer. Grabbed again before that, the drag
  # held an element the answer took out of the document, and the card that
  # came stayed wherever the pointer had it. So the block and its form are
  # inert from the drop until its answer is drawn.
  test "a block whose move is on the wire can't be grabbed again, nor its form typed into, until the answer is drawn" do
    open_editor
    find(face(@left)).click
    script_writes("hold")

    drop_into(@left, lane(2))
    await_js "typeof window.__release[0] === 'function'"
    assert_equal [ true, true ], page.evaluate_script("[ document.querySelector(#{tile(@left).to_json}).inert, document.querySelector(#{panel(@left).to_json}).inert ]")

    mouse = drag_to("#{tile(@left)} .admin-block-tile__grip", lane(1))
    await_frames # a drag that began would have put its clone on <body> by now: SortableJS makes it on the first move past its tolerance
    assert_no_selector "body > .admin-drag-fallback"
    mouse.up
    page.execute_script("window.__release[0]()")

    assert_eventually { @left.reload.section_column == 2 }
    assert_writes_settled
    assert_equal [ false, false ], page.evaluate_script("[ document.querySelector(#{tile(@left).to_json}).inert, document.querySelector(#{panel(@left).to_json}).inert ]")
    assert_equal [ @right.id, @left.id ], tiles_in(2)
    assert_equal 1, page.evaluate_script("window.__writes.length")
  end

  test "a block is free again after its move failed, and a move of an element that has left the page is no error" do
    open_editor
    script_writes("fail")

    drop_into(@left, "#content-blocks-list")

    assert_selector "#toasts .admin-toast[role=alert]", text: "Couldn't save the new order"
    assert_order_eventually([ @left.id ]) { tiles_in(1) }
    assert_equal [ false, false ], page.evaluate_script("[ document.querySelector(#{tile(@left).to_json}).inert, document.querySelector(#{panel(@left).to_json}).inert ]")

    queued = page.evaluate_script(<<~JS)
      (() => {
        const controller = #{blocks_controller}
        const item = document.querySelector(#{tile(@left).to_json})
        const from = item.parentElement
        const before = controller.snapshot()
        item.remove()
        controller.move(item, from, before)
        from.append(item)
        return controller.reordersQueued
      })()
    JS
    assert_equal 0, queued
    assert_equal 1, page.evaluate_script("window.__writes.length")
  end

  # The keyboard path steps a card among the LIST's cards. A card resting in
  # a lane, between its drop and its answer, is a card too, but no neighbour.
  test "a card stepped by the keyboard passes the list's cards only, while another rests in a lane" do
    first = @page.content_blocks.create!(block_type: "image", position: 1)
    second = @page.content_blocks.create!(block_type: "image", position: 2)
    open_editor
    script_writes("hold")

    drop_into(first, lane(1))
    await_js "typeof window.__release[0] === 'function'"
    find("#{tile(second)} .admin-block-card__handle").send_keys(:space, :up)
    assert_equal [ second.id, @section.id ], cards_in_list
    find("#{tile(second)} .admin-block-card__handle").send_keys(:space)
    page.execute_script("window.__release[0]()")

    assert_writes_settled
    assert_equal [ second.id, @section.id ], @page.content_blocks.top_level.reorder(:position).ids
    assert_equal @section.id, first.reload.section_id
  end

  # A move queued behind one that was refused was made on the screen the
  # refusal has just replaced: its lane is no longer in the page, and what it
  # would send is an order nobody is looking at.
  test "a move queued behind a refused one is not sent once the list has been redrawn" do
    open_editor
    as_unheard(users(:two)) { assert ContentBlocks::Save.call(ContentBlock.find(@section.id), attributes: { settings: { "layout" => "one" } }).ok? }
    count_writes

    page.execute_script(<<~JS)
      const controller = #{blocks_controller}
      const lane = document.querySelector(#{lane(2).to_json})
      const [left, right] = [#{@left.id}, #{@right.id}].map((id) => document.querySelector(`.admin-block-tile[data-block-id="${id}"]`))
      let before = controller.snapshot()
      const from = left.parentElement
      lane.append(left)
      controller.move(left, from, before)
      before = controller.snapshot()
      lane.append(right)
      controller.move(right, lane, before)
    JS

    assert_selector "#content-blocks-alert", text: "That section or column no longer exists"
    assert_selector "#{lane(1)} > .admin-block-tile", count: 2
    assert_writes_settled
    await_frames # the second move's turn comes when the first's answer is drawn; a request would have gone by now
    assert_equal 1, page.evaluate_script("window.__writes.length"), "the move made on the replaced screen was sent"
  end

  test "a move that never reaches the server puts the tile back in its lane and says so" do
    open_editor
    find(face(@left)).click
    script_writes("fail")

    drop_into(@left, "#content-blocks-list")

    assert_selector "#toasts .admin-toast[role=alert]", text: "Couldn't save the new order. Check your connection and try again."
    assert_order_eventually([ @left.id ]) { tiles_in(1) }
    assert_equal [ @section.id ], cards_in_list
    assert_selector panel(@left)
    assert_equal @section.id, @left.reload.section_id
  end

  # `restoreTo` is every container's order as the server last took it. A move
  # that is saved while another waits makes only ITS container's order the
  # server's: here the list's is sent while the lane's move still waits, and
  # when that one fails the lane goes back -- to what it was, not to what the
  # screen showed as the list's request went out.
  test "a move that fails behind one that was saved puts back its own lane and leaves the saved order" do
    below = @page.content_blocks.create!(block_type: "image", position: 1)
    third = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 1)
    open_editor
    # A save of a card neither move touches keeps both waiting, so the list's
    # request goes out when the lane has already been rearranged on screen.
    script_writes("hold", "pass", "fail")
    fill_in id: caption(below), with: "Held on the wire"
    page.execute_script("document.activeElement.blur()")
    await_js "typeof window.__release[0] === 'function'"

    drop_into(@section, "#content-blocks-list")
    drop_into(@left, lane(1))
    page.execute_script("window.__release[0]()")

    assert_selector "#toasts .admin-toast[role=alert]", text: "Couldn't save the new order"
    assert_order_eventually([ @left.id, third.id ]) { tiles_in(1) }
    assert_writes_settled
    assert_equal [ below.id, @section.id ], cards_in_list
    assert_equal [ below.id, @section.id ], @page.content_blocks.top_level.reorder(:position).ids
    assert_equal [ @left.id, third.id ], @page.content_blocks.in_column(@section, 1).reorder(:position).ids
    assert_equal 3, page.evaluate_script("window.__writes.length")
  end

  # The keyboard path remembers the list's order alone. A tile dragged out of
  # its lane behind it is remembered from its own drop, or it would stay in
  # the list when everything else goes back.
  test "a tile dragged out behind a keyboard move that fails goes back to its lane with the cards" do
    first = @page.content_blocks.create!(block_type: "image", position: 1)
    second = @page.content_blocks.create!(block_type: "image", position: 2)
    open_editor
    script_writes("hold", "fail", "fail")
    fill_in id: caption(first), with: "Held on the wire"
    page.execute_script("document.activeElement.blur()")
    await_js "typeof window.__release[0] === 'function'"

    find("#{tile(second)} .admin-block-card__handle").send_keys(:space, :up, :space)
    drop_into(@left, "#content-blocks-list")
    assert_equal [ @section.id, second.id, first.id, @left.id ], cards_in_list
    page.execute_script("window.__release[0]()")

    assert_selector "#toasts .admin-toast[role=alert]", text: "Couldn't save the new order"
    assert_order_eventually([ @section.id, first.id, second.id ]) { cards_in_list }
    assert_equal [ @left.id ], tiles_in(1)
    assert_writes_settled
    assert_equal 2, page.evaluate_script("window.__writes.length"), "the tile's move was sent after it had been put back"
    assert_equal @section.id, @left.reload.section_id
  end

  # The same, for a block the saved move has redrawn: the card that took the
  # tile's place is what goes back where the server has it, although every
  # order remembered from before names the tile.
  test "a card a saved move has drawn goes back where the server has it when a later move fails" do
    below = @page.content_blocks.create!(block_type: "post_list", position: 1)
    open_editor
    script_writes("hold", "hold")

    drop_into(@left, "#content-blocks-list", at: :start)
    await_js "typeof window.__release[0] === 'function'"
    drop_into(@section, "#content-blocks-list")
    page.execute_script("window.__release[0]()")
    assert_selector "#content-blocks-list > .admin-block-card[data-block-id='#{@left.id}']"
    await_js "typeof window.__release[1] === 'function'"
    assert_equal [ @left.id, @section.id, below.id ], @page.content_blocks.top_level.reorder(:position).ids

    drop_into(@left, "#content-blocks-list")
    assert_equal [ below.id, @section.id, @left.id ], cards_in_list
    page.execute_script("window.__release[1]('fail')")

    assert_selector "#toasts .admin-toast[role=alert]", text: "Couldn't save the new order"
    assert_order_eventually([ @left.id, @section.id, below.id ]) { cards_in_list }
    assert_writes_settled
    assert_equal [ @left.id, @section.id, below.id ], @page.content_blocks.top_level.reorder(:position).ids
  end

  test "a section's card can't be dropped into a lane" do
    other = @page.content_blocks.create!(block_type: "section", position: 1)
    open_editor

    allowed = page.evaluate_script(<<~JS)
      (() => {
        const controller = #{blocks_controller}
        const lane = document.getElementById("section-#{@section.id}-lane-1")
        const section = document.querySelector('.admin-block-card[data-block-id="#{other.id}"]')
        const tile = document.querySelector('.admin-block-tile[data-block-id="#{@right.id}"]')
        return [ controller.accepts(lane, section), controller.accepts(lane, tile) ]
      })()
    JS

    assert_equal [ false, true ], allowed
  end

  # What the list does with a block the pointer holds over a section's card
  # (`admin--editor--blocks#besideSection`): before it from its header, after it from
  # below its lanes, and nothing level with them -- there a lane takes it.
  test "over a section's card the list puts a dragged block before or after it only from its edges" do
    other = @page.content_blocks.create!(block_type: "section", position: 1)
    card = @page.content_blocks.create!(block_type: "image", position: 2)
    open_editor

    answers = page.evaluate_script(<<~JS)
      (() => {
        const controller = #{blocks_controller}
        const find = (id) => document.querySelector(`.admin-block-card[data-block-id="${id}"]`)
        const [section, other, card] = [#{@section.id}, #{other.id}, #{card.id}].map(find)
        const lanes = section.querySelector('[data-admin--editor--section-target="lanes"]').getBoundingClientRect()
        const ask = (dragged, related, y, willInsertAfter) => controller.besideSection({ dragged, related, willInsertAfter }, { clientY: y })
        const middle = (lanes.top + lanes.bottom) / 2
        return {
          header: [ ask(card, section, lanes.top - 2, false), ask(card, section, lanes.top - 2, true) ],
          lanes: [ ask(card, section, middle, false), ask(card, section, middle, true) ],
          below: [ ask(card, section, lanes.bottom + 2, false), ask(card, section, lanes.bottom + 2, true) ],
          sectionOverSection: ask(other, section, middle, true),
          overPlainCard: ask(section, card, middle, true)
        }
      })()
    JS

    assert_equal({ "header" => [ true, false ], "lanes" => [ false, false ], "below" => [ false, true ],
      "sectionOverSection" => true, "overPlainCard" => true }, answers)
  end
end
