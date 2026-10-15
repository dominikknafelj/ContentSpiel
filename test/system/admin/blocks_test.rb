require "application_system_test_case"

# The page editor's block list (cs-studio spec §5.1/§9): adding a block
# through the picker (a plain form submission, `admin--editor--blocks` itself has no
# hand in it) and drag-reordering existing ones (`admin--editor--blocks#reorder`).
class Admin::BlocksSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "About")
  end

  test "adding a block through the picker shows the card and persists" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    # The end-of-list picker (`after_id` absent) is open by default -- no
    # disclosure click needed before its own type buttons are visible.
    # Every button here is a plain `button_to` (`Admin::EditorScreen::BlockPickerComponent`'s
    # own comment): Turbo Drive already appends the Turbo Stream `Accept`
    # header to a non-GET form submission on its own, so this is a normal
    # submit, not a fetch this test would otherwise have to wait on by hand.
    press "Rich text"

    assert_selector ".admin-block-card", text: "Rich text"
    assert_equal 1, @page.content_blocks.count
    assert_equal "rich_text", @page.content_blocks.first.block_type

    # Reload the whole editor (a fresh GET, not just trusting the Turbo
    # Stream response) to prove the card is actually persisted, not only
    # reflecting the in-memory DOM this session just built.
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    assert_selector ".admin-block-card", text: "Rich text"
  end

  test "the Add block row appends an Image block at the end, with Move down disabled on it and enabled on the one before" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    assert_selector "#{card_for(first)} button[data-move='down'][disabled]", visible: :all
    within("#block-picker-end") { press "Image" }

    assert_selector "#content-blocks-list > .admin-block-card", count: 2
    added = @page.content_blocks.where.not(id: first.id).sole
    assert_equal "image", added.block_type
    assert_equal [ first.id, added.id ], page.all("#content-blocks-list > [data-block-id]").map { |c| c["data-block-id"].to_i }
    assert_selector "#{card_for(added)} button[data-move='down'][disabled]", visible: :all
    assert_no_selector "#{card_for(first)} button[data-move='down'][disabled]", visible: :all
    assert_no_selector "[id^='block-picker-after-']"
  end

  test "the card menu's Delete block… asks first, then removes the card" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    find("#{card_for(first)} button[aria-label='Block actions']").click
    within(card_for(first)) { press "Delete block…" }
    assert_text "Delete this block?"
    assert_text "Blocks don’t go to the trash."
    within("dialog[open]") { press "Delete block" }

    assert_no_selector card_for(first)
    assert_equal [ second ], @page.content_blocks.reload.to_a
    # The remaining card is now the only one: neither move is possible.
    assert_selector "#{card_for(second)} button[data-move='up'][disabled]", visible: :all
    assert_selector "#{card_for(second)} button[data-move='down'][disabled]", visible: :all
  end

  test "the menu's Duplicate inserts the copy right below the source" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    find("#{card_for(first)} button[aria-label='Block actions']").click
    within(card_for(first)) { press "Duplicate" }

    assert_selector "#content-blocks-list > .admin-block-card", count: 3
    copy = (@page.content_blocks.reload.to_a - [ first, second ]).sole
    assert_equal [ first, copy, second ], @page.content_blocks.to_a
    assert_equal [ first.id, copy.id, second.id ], page.all("#content-blocks-list > [data-block-id]").map { |c| c["data-block-id"].to_i }
  end

  # Ledger b6 (final fix wave 1): a reorder queued behind an Add (or Duplicate
  # or Delete) still in flight reads the card list when it is SENT. The queue
  # used to let it go as soon as the Add was answered -- but Turbo applies that
  # answer's stream a frame later, so the reorder listed the cards WITHOUT the
  # new one, the server refused it (422, "must list exactly this page's
  # blocks"), and the order on screen was one that had not been saved.
  test "a Move queued behind an Add block still in flight is sent with the new card in the list" do
    first = @page.content_blocks.create!(block_type: "image", position: 0)
    second = @page.content_blocks.create!(block_type: "image", position: 1)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__statuses = []
      window.fetch = async (url, options = {}) => {
        const write = (options.method || "GET").toUpperCase() !== "GET"
        if (write) await new Promise((resolve) => setTimeout(resolve, 600))
        const response = await originalFetch(url, options)
        if (write) window.__statuses.push(response.status)
        return response
      }
    JS

    # One tick: the Add goes out (and is slow), then Move down on the first card.
    page.execute_script(<<~JS)
      Array.from(document.querySelectorAll("#block-picker-end button")).find((b) => b.textContent.trim() === "Rich text").click()
      document.querySelector('[data-block-id="#{first.id}"] [data-move="down"]').click()
    JS

    assert_selector "#content-blocks-list > .admin-block-card", count: 3, wait: 10
    assert_eventually(wait: 10) { page.evaluate_script("window.__statuses.length") == 2 }
    added = @page.content_blocks.where.not(id: [ first.id, second.id ]).sole
    assert_equal [ 201, 200 ], page.evaluate_script("window.__statuses"), "the reorder was refused"
    assert_equal [ second.id, first.id, added.id ], @page.content_blocks.reload.order(:position).ids
    assert_equal [ second.id, first.id, added.id ], page.all("#content-blocks-list > [data-block-id]").map { |c| c["data-block-id"].to_i }
  end

  # Task 12's b5: a card's menu Move pressed while that card's own autosave is
  # still out. The reorder waits behind the save (one write queue per
  # screen), the save lands, then the move: both persist, the typed caption
  # on the moved card included.
  test "a menu Move queued behind an in-flight autosave waits for it, then both land" do
    first = @page.content_blocks.create!(block_type: "image", position: 0)
    second = @page.content_blocks.create!(block_type: "image", position: 1)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__writes = []
      window.fetch = (url, options = {}) => {
        const method = (options.method || "GET").toUpperCase()
        if (method === "GET") return originalFetch(url, options)
        if (String(url.url || url).includes("/cs-studio/editing/")) return originalFetch(url, options) // a claim is not the save the move waits behind
        window.__writes.push(method)
        if (method !== "PATCH" || window.__writes.filter((m) => m === "PATCH").length > 1) return originalFetch(url, options)
        return new Promise((resolve) => { window.__releaseSave = () => resolve(originalFetch(url, options)) })
      }
    JS

    caption = find("[data-block-id='#{first.id}'] textarea[name='block[caption]'], [data-block-id='#{first.id}'] input[name='block[caption]']")
    caption.set("Typed before the move")
    caption.send_keys(:tab)
    await_js "typeof window.__releaseSave === 'function'"
    find("[data-block-id='#{first.id}'] button[aria-label='Block actions']").click
    find("[data-block-id='#{first.id}'] [data-move='down']").click
    await_frames # the click has been handled: the move is queued behind the held save, or it would have been sent by now
    assert_equal [ "PATCH" ], page.evaluate_script("window.__writes"), "the move was sent before the save it queued behind finished"

    page.execute_script("window.__releaseSave()")
    assert_eventually(wait: 10) { @page.content_blocks.reload.order(:position).ids == [ second.id, first.id ] }
    assert_equal "Typed before the move", first.reload.caption
    assert_equal [ "PATCH", "PATCH" ], page.evaluate_script("window.__writes")
  end

  # Ledger m2 (final fix wave 1): moving a card in the DOM (a drag, Move
  # up/down) disconnects and reconnects its form's `admin--saving--autosave`. The
  # reconnect used to take whatever the form held for "what the server
  # holds", and the disconnect had cleared the debounce timer: an edit made
  # by code inside its debounce (a translation's Use, with focus elsewhere)
  # was never sent -- not by the timer, not by a later `focusout`, not by the
  # drain before a visit.
  test "an edit still inside its debounce survives its card being moved" do
    first = @page.content_blocks.create!(block_type: "image", position: 0)
    second = @page.content_blocks.create!(block_type: "image", position: 1)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    page.execute_script(<<~JS)
      const field = document.getElementById("block-#{second.id}-caption")
      field.value = "Set by code, then the card moved"
      field.dispatchEvent(new Event("input", { bubbles: true }))
      document.querySelector('[data-block-id="#{second.id}"] [data-move="up"]').click()
    JS

    assert_eventually { @page.content_blocks.reload.order(:position).ids == [ second.id, first.id ] }
    assert_eventually { second.reload.caption == "Set by code, then the card moved" }
    assert_no_text "CHANGED ELSEWHERE"
  end

  # Follow-up N4: what survives a card being moved is the form's whole save
  # state, not only its signature. A card paused by a 409 ("Changed
  # elsewhere" -- its saves are over until Reload) used to come back from the
  # move un-paused, and the restart of the debounce sent its text again.
  test "a card paused by Changed elsewhere stays paused when it is moved" do
    first = @page.content_blocks.create!(block_type: "image", position: 0)
    second = @page.content_blocks.create!(block_type: "image", position: 1)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__blockPatches = 0
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() === "PATCH" && String(url.url || url).includes("/content_blocks/#{second.id}")) window.__blockPatches += 1
        return originalFetch(url, options)
      }
    JS
    travel 1.minute do
      as_unheard(users(:two)) { ContentBlocks::Save.call(second, translations: { "en" => { caption: "The other editor's caption" } }) }
    end

    fill_in id: "block-#{second.id}-caption", with: "My caption"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{second.id}-save-status", text: "CHANGED ELSEWHERE", wait: 8
    assert_equal 1, page.evaluate_script("window.__blockPatches")

    find("[data-block-id='#{second.id}'] button[aria-label='Block actions']").click
    find("[data-block-id='#{second.id}'] [data-move='up']").click
    assert_eventually { @page.content_blocks.reload.order(:position).ids == [ second.id, first.id ] }
    sleep 1.1 # sleep: the autosave debounce is 1 s; the card is paused by the 409, so not settled, and nothing marks the expiry of a timer that must not run
    fill_in id: "block-#{second.id}-caption", with: "My caption, edited again"
    page.execute_script("document.activeElement.blur()")
    await_frames # the blur's save, if the paused card still sent one, goes out on the focusout itself

    assert_equal 1, page.evaluate_script("window.__blockPatches"), "a paused card sent again after it was moved"
    assert_equal "The other editor's caption", second.reload.caption
  end

  # Deferred b3: Duplicate is picked from the card's menu, which closes -- and
  # focus fell to <body>. It goes to the copy's handle, where Space and the
  # arrows move it on.
  test "after Duplicate focus is on the copy's handle" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    find("#{card_for(first)} button[aria-label='Block actions']").click
    within(card_for(first)) { press "Duplicate" }

    assert_selector "#content-blocks-list > .admin-block-card", count: 2
    copy = @page.content_blocks.where.not(id: first.id).sole
    assert_selector "#{card_for(copy)} .admin-block-card__handle:focus"
  end

  test "the type name collapses and expands the body, and says which" do
    block = @page.content_blocks.create!(block_type: "post_list", position: 0)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    title = "#{card_for(block)} button[aria-controls]"
    assert_selector "#{title}[aria-expanded='true']"
    find(title).click
    assert_selector "#{title}[aria-expanded='false']"
    assert_no_selector "#{card_for(block)} [data-block-body]", visible: :visible
    find(title).click
    assert_selector "#{card_for(block)} [data-block-body]"
  end

  test "a post list's tag is a single-value chip input: choosing replaces, removing clears, and both save" do
    Current.set(actor: users(:one)) do
      create_post(title: "One", tags: [ "news", "events" ])
    end
    block = @page.content_blocks.create!(block_type: "post_list", position: 0)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    within(card_for(block)) do
      field = find("input[role=combobox]")
      field.send_keys("new")
      find("[role=option]", text: "news").click
    end
    assert_selector "#block-#{block.id}-save-status", text: /SAVED/, wait: 10
    assert_equal "news", block.reload.settings["tag"]

    within(card_for(block)) do
      find("input[role=combobox]").send_keys("eve")
      find("[role=option]", text: "events").click
      assert_selector "li[data-chip-value]", count: 1
      assert_selector "li[data-chip-value='events']"
    end
    assert_eventually { block.reload.settings["tag"] == "events" }

    within(card_for(block)) { find("button[aria-label='Remove events']").click }
    assert_eventually { block.reload.settings["tag"].to_s == "" }
  end

  test "an image block's alt override shows the library text as placeholder and Reset clears it" do
    asset = create_media_asset
    asset.update!(alt: "Library alt")
    block = @page.content_blocks.create!(block_type: "image", position: 0, media_asset: asset)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    alt = "#block-#{block.id}-alt"
    assert_selector "#{alt}[placeholder='Library alt']"
    find(alt).set("Mine")
    find(alt).send_keys(:tab)
    assert_eventually { block.reload.alt(locale: :en) == "Mine" }
    within(card_for(block)) { press "Reset" }
    assert_eventually { block.reload.alt(locale: :en).to_s == "" }
    assert_equal "", find(alt).value
  end

  test "dragging a block's handle reorders the list and persists" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "post_list", position: 1)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    assert_selector "#content-blocks-list .admin-block-card:first-child[data-block-id='#{first.id}']"

    # `admin--editor--blocks` drives SortableJS with no `forceFallback` option (see
    # that controller's own source), so a drag here is the browser's native
    # HTML5 drag-and-drop under the hood -- `dragstart`/`dragover`/`drop`
    # events a synthesized mouse sequence (Capybara's `drag_to`) can't
    # reliably trigger in headless Chrome, native DnD being a
    # browser-internal mechanism rather than a sequence of ordinary mouse
    # events. Driving the Stimulus controller's own `reorder()` directly,
    # right after moving the two cards' DOM nodes into the order a real
    # drop would leave them in, exercises the exact same production code
    # (a hand-built `fetch` PATCH, applied via `Turbo.renderStreamMessage`)
    # a drag's own `onEnd` calls -- the brief's own sanctioned fallback for
    # exactly this situation.
    page.execute_script(<<~JS)
      const list = document.getElementById("content-blocks-list")
      const secondCard = list.querySelector('[data-block-id="#{second.id}"]')
      const firstCard = list.querySelector('[data-block-id="#{first.id}"]')
      list.insertBefore(secondCard, firstCard)

      const section = document.querySelector('[data-controller~="admin--editor--blocks"]')
      window.Stimulus.getControllerForElementAndIdentifier(section, "admin--editor--blocks").reorder()
    JS

    # `assert_selector(id, text:, wait:)`, not `within(id) { assert_text }`
    # -- see `test/system/admin/autosave_test.rb`'s own comment for why the
    # two-step form can raise `ElementNotFound` before its own explicit
    # wait gets any say.
    assert_selector "#content-blocks-status", text: "SAVED"
    assert_selector "#content-blocks-list .admin-block-card:first-child[data-block-id='#{second.id}']"
    assert_equal [ second, first ], @page.content_blocks.reload.order(:position).to_a
  end
  # Final fix wave I3 / fix round 2: every block write touches the page, so
  # each block request sends the page form's base along and gets it moved
  # forward when it was current -- through Turbo's own submissions (the
  # picker) and a card's autosave alike. Without that, the page form's next
  # save here would read "Changed elsewhere" with nobody else involved.
  test "editing blocks doesn't make the page settings form report a false conflict" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    press "Post list"
    assert_selector ".admin-block-card", text: "Post list"
    block = @page.content_blocks.sole

    within("##{ActionView::RecordIdentifier.dom_id(block)}") { find("input[name='block[settings][limit]']").fill_in(with: "4") }
    assert_selector "#block-#{block.id}-save-status", text: /\A(● )?SAVED( · NOT PUBLISHED)? \d{2}:\d{2}\z/, wait: 5
    assert_equal 4, block.reload.settings["limit"].to_i

    fill_in "Title", with: "About the Studio"
    assert_selector "#page-save-status", text: /\A(● )?SAVED( · NOT PUBLISHED)? \d{2}:\d{2}\z/, wait: 5
    assert_no_text "CHANGED ELSEWHERE"
    assert_no_selector "#changed-elsewhere"
    assert_equal "About the Studio", @page.reload.title(locale: :en)
  end
  # Fix round 3: a card's queued follow-up save (`admin--saving--autosave`'s
  # `pending` retrigger) runs before Turbo applies the previous response's
  # streams (next animation frame), so it used to send the page form's
  # *old* base -- the server then rightly refused to move it, the write
  # touched the page again, and the page form's next save read "Changed
  # elsewhere" with nobody else involved. The first PATCH is held (same
  # JS-side stub as `autosave_test.rb`'s in-flight test) so the follow-up
  # is certain to be queued behind it.
  test "a queued block save doesn't make the page settings form report a false conflict" do
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    press "Post list"
    assert_selector ".admin-block-card", text: "Post list"
    block = @page.content_blocks.sole

    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__patchesStarted = 0
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() !== "PATCH") return originalFetch(url, options)

        window.__patchesStarted += 1
        if (window.__patchesStarted > 1) return originalFetch(url, options)
        return new Promise((resolve) => { window.__releaseFirstPatch = () => resolve(originalFetch(url, options)) })
      }
    JS

    limit = find("##{ActionView::RecordIdentifier.dom_id(block)} input[name='block[settings][limit]']")
    limit.set("4")
    limit.send_keys(:tab)
    await_js "typeof window.__releaseFirstPatch === 'function'"
    limit = find("##{ActionView::RecordIdentifier.dom_id(block)} input[name='block[settings][limit]']")
    limit.set("5")
    limit.send_keys(:tab)
    assert_equal 1, page.evaluate_script("window.__patchesStarted")

    page.execute_script("window.__releaseFirstPatch()")
    await_js "window.__patchesStarted === 2"
    assert_selector "#block-#{block.id}-save-status", text: /\A(● )?SAVED( · NOT PUBLISHED)? \d{2}:\d{2}\z/, wait: 5
    assert_eventually { block.reload.settings["limit"].to_i == 5 }

    fill_in "Title", with: "About the Studio"
    assert_selector "#page-save-status", text: /\A(● )?SAVED( · NOT PUBLISHED)? \d{2}:\d{2}\z/, wait: 5
    assert_no_text "CHANGED ELSEWHERE"
    assert_no_selector "#changed-elsewhere"
  end

  private

  def card_for(block) = "##{ActionView::RecordIdentifier.dom_id(block)}"

  # Task 12's b4: a post list's Limit is a 72px column; its error slot hangs
  # from the column's right edge and runs leftwards instead of wrapping word by
  # word in 72px.
  test "the Limit error is wider than its 72px column and ends at the column's right edge" do
    block = @page.content_blocks.create!(block_type: "post_list", position: 0, settings: { "limit" => 3 })
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    card = "##{ActionView::RecordIdentifier.dom_id(block)}"
    find("#{card} input[name='block[settings][limit]']").set("0")
    find("#{card} input[name='block[settings][limit]']").send_keys(:tab)
    assert_selector "##{Admin::EditorScreen::BlockCardComponent.error_prefix(block)}-limit-errors p", wait: 6

    rects = page.evaluate_script(<<~JS)
      (() => {
        const error = document.querySelector("##{Admin::EditorScreen::BlockCardComponent.error_prefix(block)}-limit-errors").getBoundingClientRect()
        const input = document.querySelector("#{card} input[name='block[settings][limit]']").getBoundingClientRect()
        return { errorWidth: error.width, errorRight: error.right, inputRight: input.right }
      })()
    JS
    assert_operator rects["errorWidth"], :>, 120
    assert_in_delta rects["inputRight"], rects["errorRight"], 2
  end

  # Design answer, first reply: a tall empty gap between a card's header and
  # its first label (the reserved save line, Ruling 20).
  test "a card's first label stands just under its header" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers

    gap = page.evaluate_script(<<~JS)
      (() => {
        const card = document.getElementById(#{ActionView::RecordIdentifier.dom_id(block).to_json})
        const head = card.querySelector(".admin-block-card__head").getBoundingClientRect()
        const label = card.querySelector("[data-field-name='body'] p").getBoundingClientRect()
        return label.top - head.bottom
      })()
    JS
    assert_operator gap, :<=, 16
  end

  # Review focus 2.
  test "a long save message wraps in the header and leaves the menu inside the card" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
    card = "##{ActionView::RecordIdentifier.dom_id(block)}"
    status = "##{Admin::EditorScreen::BlockCardComponent.status_id(block)}"

    page.execute_script(<<~JS)
      document.querySelector(#{card.to_json}).style.width = "360px"
      document.querySelector(#{status.to_json}).textContent = "SAVED · ALSO CHANGED ELSEWHERE — RELOAD TO SEE THE LATEST"
    JS
    inside = page.evaluate_script(<<~JS)
      (() => {
        const card = document.querySelector(#{card.to_json}).getBoundingClientRect()
        const menu = document.querySelector(#{card.to_json} + " .admin-block-card__head button[aria-label='Block actions']").getBoundingClientRect()
        return menu.width > 0 && menu.right <= card.right + 0.5
      })()
    JS
    assert inside, "the Block actions button left the card"
  ensure
    page.execute_script("document.querySelector(#{card.to_json})?.style.removeProperty('width')") if card
  end
end
