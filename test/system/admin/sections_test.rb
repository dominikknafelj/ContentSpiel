require "application_system_test_case"

# A section in the page editor (sections spec §4): lanes of tiles with one
# block's form open under them. The forms are all in the page from the start
# (hidden), so these tests are about what showing and hiding one does to its
# autosave -- nothing, except that closing sends what it holds.
class Admin::SectionsSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "Landing")
    @section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    @left = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 0)
    @right = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 2, position: 0)
  end

  def open_editor
    visit "/cs-studio/pages/#{@page.id}"
    await_admin_controllers
  end

  def tile(block) = "##{ActionView::RecordIdentifier.dom_id(block)}"
  def face(block) = "#{tile(block)} .admin-block-tile__face"
  def panel(block) = "#block-#{block.id}-panel"
  def caption(block) = "block-#{block.id}-caption"

  # Holds the first PATCH this page sends until `window.__releaseSave()`.
  def hold_first_save
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__writes = []
      window.fetch = (url, options = {}) => {
        const method = (options.method || "GET").toUpperCase()
        if (method === "GET") return originalFetch(url, options)
        window.__writes.push(String(url.url || url))
        if (window.__writes.length > 1) return originalFetch(url, options)
        return new Promise((resolve) => { window.__releaseSave = () => resolve(originalFetch(url, options)) })
      }
    JS
  end

  # Records every write this page sends from now on, and lets it through.
  def count_writes
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__writes = []
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() !== "GET") window.__writes.push(String(url.url || url))
        return originalFetch(url, options)
      }
    JS
  end

  test "a section shows a tile per block in its lane and no form until a tile is pressed" do
    open_editor

    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", count: 1
    assert_selector "#section-#{@section.id}-lane-2 > .admin-block-tile", count: 1
    assert_no_selector panel(@left)
    assert_selector panel(@left), visible: :all

    find(face(@left)).click

    assert_selector panel(@left), text: "Image · column 1"
    assert_selector "#{face(@left)}[aria-expanded='true']"
    assert_no_selector panel(@right)
  end

  test "typing in the open form autosaves like a card" do
    open_editor
    find(face(@left)).click

    fill_in id: caption(@left), with: "A caption from a tile"
    page.execute_script("document.activeElement.blur()")

    assert_selector "#block-#{@left.id}-save-status", text: "SAVED"
    assert_equal "A caption from a tile", @left.reload.caption
  end

  test "opening another tile closes the first and sends an edit still inside its debounce" do
    open_editor
    find(face(@left)).click
    page.execute_script(<<~JS)
      const field = document.getElementById(#{caption(@left).to_json})
      field.value = "Set by code, then the form was switched"
      field.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    find(face(@right)).click

    assert_no_selector panel(@left)
    assert_selector panel(@right)
    assert_writes_settled
    assert_equal "Set by code, then the form was switched", @left.reload.caption
    assert_no_text "CHANGED ELSEWHERE"
  end

  test "a save in flight when the form is switched lands, and so does the next form's" do
    open_editor
    hold_first_save
    find(face(@left)).click
    fill_in id: caption(@left), with: "First, held on the wire"
    page.execute_script("document.activeElement.blur()")
    await_js "typeof window.__releaseSave === 'function'"

    find(face(@right)).click
    fill_in id: caption(@right), with: "Second, queued behind it"
    page.execute_script("document.activeElement.blur()")
    await_frames # the second save is queued behind the held one, or it would have been sent by now
    assert_equal 1, page.evaluate_script("window.__writes.length"), "the second form's save went out beside the first"

    page.execute_script("window.__releaseSave()")
    assert_writes_settled
    assert_equal [ "First, held on the wire", "Second, queued behind it" ], [ @left.reload.caption, @right.reload.caption ]
    assert_equal 2, page.evaluate_script("window.__writes.length")
  end

  # Review Focus 2.
  test "a form paused by Changed elsewhere keeps its text and its status through a close and reopen" do
    open_editor
    find(face(@left)).click
    travel 1.minute do
      as(users(:two), channel: :admin) { ContentBlocks::Save.call(@left, translations: { "en" => { caption: "The other editor's caption" } }) }
    end
    fill_in id: caption(@left), with: "Mine, refused"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE", wait: 8
    count_writes

    find(face(@right)).click
    find(face(@left)).click

    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE"
    assert_field caption(@left), with: "Mine, refused"
    assert_equal "The other editor's caption", @left.reload.caption
    await_frames # a close that sent the paused form would have called fetch by now: `saveNow` runs inside the click
    assert_equal [], page.evaluate_script("window.__writes"), "the paused form was sent again"
  end

  test "Escape and a press on the open tile close the form and give the tile the focus" do
    open_editor
    find(face(@left)).click
    find(id: caption(@left)).send_keys(:escape)

    assert_no_selector panel(@left)
    assert_selector "#{face(@left)}[aria-expanded='false']"
    assert_equal true, page.evaluate_script("document.activeElement === document.querySelector(#{face(@left).to_json})")

    find(face(@left)).click
    assert_selector panel(@left)
    find(face(@left)).click
    assert_no_selector panel(@left)
  end

  # Review Focus 3.
  test "Escape inside an open menu of the form closes the menu, not the form" do
    text = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    open_editor
    find(face(text)).click
    menu_button = find("#{panel(text)} [role=toolbar] button[aria-haspopup=menu]", match: :first)
    menu_button.click
    assert_selector "#{panel(text)} [role=toolbar] [role=menu]"

    menu_button.send_keys(:escape)

    assert_no_selector "#{panel(text)} [role=toolbar] [role=menu]"
    assert_selector panel(text)
  end

  # The debounce is made longer than any wait here, so the save can only have
  # been sent by the close itself: the write queue is not settled while a
  # debounce is running, however fast or slow the machine.
  test "closing sends what the form holds at once, without waiting for its debounce" do
    open_editor
    find(face(@left)).click
    page.execute_script(<<~JS)
      const field = document.getElementById(#{caption(@left).to_json})
      field.form.setAttribute("data-admin--autosave-debounce-value", "600000")
      field.value = "Sent by the close"
      field.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    within(panel(@left)) { press "Close" }

    assert_no_selector panel(@left)
    assert_writes_settled
    assert_equal "Sent by the close", @left.reload.caption
    assert_equal true, page.evaluate_script("document.activeElement === document.querySelector(#{face(@left).to_json})")
  end

  # The section's card is moved in the DOM by `admin--blocks`, which
  # disconnects and reconnects every tile and panel of `admin--section`. The
  # open form must still be the one form open afterwards: pressing another
  # tile closes it instead of opening a second one beside it.
  test "a section moved with a form open still has one form open, and the next tile closes it" do
    below = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    open_editor
    find(face(@left)).click
    fill_in id: caption(@left), with: "Typed before the move"

    find("#{tile(@section)} > div:first-child .admin-block-card__handle").send_keys(:space, :down, :space)

    assert_writes_settled
    assert_equal [ below.id, @section.id ], @page.content_blocks.top_level.reorder(:position).ids
    assert_selector panel(@left)
    assert_selector "#{face(@left)}[aria-expanded='true']"
    assert_equal "Typed before the move", @left.reload.caption

    find(face(@right)).click

    assert_selector panel(@right)
    assert_no_selector panel(@left)
    assert_selector "#{face(@left)}[aria-expanded='false']"
    assert_selector "#section-#{@section.id}-panels > [data-admin--section-target='panel']", count: 1
  end

  # A save refused as invalid leaves its error in a form that closing hides,
  # so the tile says it; and the form is still the failed one when reopened,
  # with the error beside its field, and saves once the value is put right.
  test "an invalid save is marked on the tile while its form is closed, and cleared by the save that fixes it" do
    list = @page.content_blocks.create!(block_type: "post_list", section: @section, section_column: 2, position: 1)
    limit = "#{panel(list)} input[name='block[settings][limit]']"
    open_editor
    find(face(list)).click
    find(limit).set("0")
    find(limit).send_keys(:escape)

    assert_no_selector panel(list)
    assert_selector "#{tile(list)} .admin-block-tile__summary", text: "Needs fixing"
    assert_selector "#{tile(list)} [aria-label='Needs attention']"

    find(face(list)).click
    assert_selector "#block-#{list.id}-limit-errors", text: "must be greater than or equal to 1"
    find(limit).set("3")
    find(limit).send_keys(:escape)

    assert_writes_settled
    assert_no_selector "#{tile(list)} .admin-block-tile__summary", text: "Needs fixing"
    assert_equal 3, list.reload.settings["limit"].to_i
  end

  # Review Focus 3, the other half: a suggestion list.
  test "Escape inside an open suggestion list of the form closes the list, not the form" do
    create_post(title: "Tagged", tags: [ "rails" ])
    list = @page.content_blocks.create!(block_type: "post_list", section: @section, section_column: 2, position: 1)
    open_editor
    find(face(list)).click
    search = find("#{panel(list)} input[role=combobox]")
    search.send_keys("rai")
    assert_selector "#{panel(list)} [role=listbox] [role=option]", text: "rails"

    search.send_keys(:escape)

    assert_no_selector "#{panel(list)} [role=listbox] [role=option]"
    assert_selector panel(list)

    search.send_keys(:escape)

    assert_no_selector panel(list)
  end

  # An unavailable block's panel has the block's one action, "Delete block…",
  # so the block is deleted from inside the form that is open. The panel goes
  # with the tile: left behind it would stay open with no tile to close it
  # from. With it gone no form is open, and the next tile opens as the first.
  test "deleting an unavailable block from its open panel removes its tile and the panel, and no form is left open" do
    gone = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    gone.update_column(:block_type, "gone/thing")
    open_editor
    find(face(gone)).click
    assert_selector panel(gone), text: "Unavailable type — gone/thing"

    within(panel(gone)) { press "Delete block…" }
    within("dialog[open]") { press "Delete block" }

    assert_no_selector tile(gone)
    assert_no_selector panel(gone), visible: :all
    assert_no_selector "#section-#{@section.id}-panels > [data-admin--section-target='panel']"
    assert_not ContentBlock.exists?(gone.id)
    # The header counted three; the delete's answer brings the new count.
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 2 blocks", exact_text: true

    find(face(@left)).click

    assert_selector panel(@left)
    assert_selector "#section-#{@section.id}-panels > [data-admin--section-target='panel']", count: 1
  end

  test "a section is added from the picker and a block added to its second lane opens at once" do
    plain = create_page(title: "Built by hand")
    visit "/cs-studio/pages/#{plain.id}"
    await_admin_controllers

    within("#block-picker-end") { press "Section" }
    assert_selector ".admin-section-card [data-admin--blocks-target='lane']", count: 2
    section = plain.content_blocks.sole

    find("#block-picker-#{section.id}-2 button[aria-haspopup=menu]").click
    within("#block-picker-#{section.id}-2") { press "Image" }

    assert_selector "#section-#{section.id}-lane-2 > .admin-block-tile", count: 1
    block = section.section_blocks.reload.sole
    assert_selector "#block-#{block.id}-panel", text: "Image · column 2"
    assert_selector "#{face(block)}[aria-expanded='true']"
    assert_selector "#section-#{section.id}-summary", text: "2 columns · 1 block"
    # The menu closed on the pick, and the form's first field has the focus.
    assert_no_selector "#block-picker-#{section.id}-2 [role=menu]"
    assert_equal true, page.evaluate_script("document.getElementById(#{"block-#{block.id}-panel".to_json}).contains(document.activeElement)")

    fill_in id: "block-#{block.id}-caption", with: "Typed straight away"
    page.execute_script("document.activeElement.blur()")
    assert_writes_settled
    assert_equal "Typed straight away", block.reload.caption
    assert_no_text "CHANGED ELSEWHERE"
  end

  test "a second block added to a lane closes the form that was open, saving it" do
    open_editor
    find(face(@left)).click
    page.execute_script(<<~JS)
      const field = document.getElementById(#{caption(@left).to_json})
      field.value = "Held when the next block was added"
      field.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    find("#block-picker-#{@section.id}-1 button[aria-haspopup=menu]").click
    within("#block-picker-#{@section.id}-1") { press "Rich text" }

    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", count: 2
    assert_no_selector panel(@left)
    assert_selector "#{face(@left)}[aria-expanded='false']"
    assert_selector "#section-#{@section.id}-panels > [data-admin--section-target='panel']", count: 1
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 3 blocks"
    assert_writes_settled
    assert_equal "Held when the next block was added", @left.reload.caption
  end

  # A lane's "+" offers what may go into a section, which a section is not.
  test "a lane's picker offers no Section" do
    open_editor
    find("#block-picker-#{@section.id}-1 button[aria-haspopup=menu]").click

    assert_selector "#block-picker-#{@section.id}-1 [role=menu] [role=menuitem]", text: "Rich text"
    assert_no_selector "#block-picker-#{@section.id}-1 [role=menu] [role=menuitem]", text: "Section"
  end

  # Review Focus of the sections plan: two tabs. This one was loaded while
  # the section had four columns and still shows the "+" of the fourth;
  # another has folded it to two since. The add is refused and says why, no
  # block is made, and the lanes are redrawn as they are now -- under a form
  # that was open and stays open, its tile still saying so.
  test "an add into a column folded away elsewhere is refused with a message, and the lanes are redrawn as they are" do
    @section.update!(settings: @section.settings.merge("layout" => "four"))
    far = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 4, position: 0)
    open_editor
    assert_selector "#section-#{@section.id}-lanes [data-admin--blocks-target='lane']", count: 4
    find(face(@left)).click
    as(users(:two), channel: :admin) { assert ContentBlocks::Save.call(ContentBlock.find(@section.id), attributes: { settings: { "layout" => "two" } }).ok? }
    assert_equal 2, far.reload.section_column

    find("#block-picker-#{@section.id}-4 button[aria-haspopup=menu]").click
    within("#block-picker-#{@section.id}-4") { press "Image" }

    assert_selector "#content-blocks-alert", text: "isn't a column of this section"
    assert_selector "#section-#{@section.id}-lanes [data-admin--blocks-target='lane']", count: 2
    assert_equal [ @right.id, far.id ], page.all("#section-#{@section.id}-lane-2 > .admin-block-tile").map { |tile| tile["data-block-id"].to_i }
    assert_no_selector "#block-picker-#{@section.id}-4", visible: :all
    assert_selector panel(@left)
    assert_selector "#{face(@left)}[aria-expanded='true']"
    assert_equal [ @left.id, @right.id, far.id ].sort, @section.section_blocks.reload.ids.sort
  end

  # ---- The section's own controls (sections spec §4.1) ----

  def section_card = "##{ActionView::RecordIdentifier.dom_id(@section)}"
  def layout_button = "#{section_card} button[aria-label='Layout']"

  def focus_is_on(selector) = page.evaluate_script("document.activeElement === document.querySelector(#{selector.to_json})")

  test "choosing a narrower layout folds the second lane into the first without losing the open form" do
    open_editor
    find(face(@right)).click
    fill_in id: caption(@right), with: "Typed before the fold"

    find("##{ActionView::RecordIdentifier.dom_id(@section)} button[aria-label='Layout']").click
    find("button[data-admin--section-layout-param='one']").click

    assert_selector "#section-#{@section.id}-lanes [data-admin--blocks-target='lane']", count: 1
    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", count: 2
    assert_selector panel(@right), text: "Image · column 1"
    assert_selector "#section-#{@section.id}-summary", text: "1 column · 2 blocks"
    assert_writes_settled
    assert_equal [ 1, "Typed before the fold" ], @right.reload.then { |block| [ block.section_column, block.caption ] }
    assert_field caption(@right), with: "Typed before the fold"
  end

  # The fold moved the block and wrote nothing else of it: the form that was
  # open goes on saving on the base it had, with no "Changed elsewhere", and
  # its tile -- redrawn with the lanes -- still says it is the open one.
  test "after a fold the open form still saves, its tile says it is open, and the menu shows the new layout" do
    open_editor
    find(face(@right)).click
    find(layout_button).click
    find("button[data-admin--section-layout-param='one']").click
    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", count: 2

    assert_selector "#{face(@right)}[aria-expanded='true']"
    assert_selector "#{face(@left)}[aria-expanded='false']"
    fill_in id: caption(@right), with: "Typed after the fold"
    page.execute_script("document.activeElement.blur()")

    assert_selector "#block-#{@right.id}-save-status", text: "SAVED"
    assert_no_text "CHANGED ELSEWHERE"
    assert_equal "Typed after the fold", @right.reload.caption
    find(layout_button).click
    assert_selector "#{section_card} button[data-admin--section-layout-param='one'][aria-current='true']"
    assert_selector "#{section_card} button[data-admin--section-layout-param][aria-current='true']", count: 1
    assert_equal "one", @section.reload.settings["layout"]
  end

  # The item that was pressed is in a menu that closes on the pick, and the
  # menu itself is replaced by the answer: without a rule the focus is on
  # <body> twice over. It stays on the Layout button -- the old one at once,
  # the one the answer brings afterwards.
  test "the layout menu is worked by the keyboard, and the focus stays on its button through the answer" do
    open_editor
    # Focused by script and opened with the key alone: `send_keys` on an
    # element clicks it first, which would be the pointer opening the menu.
    page.execute_script("document.querySelector(#{layout_button.to_json}).focus()")
    page.driver.browser.keyboard.type(:enter)
    assert_selector "#{section_card} [role=menu] [role=menuitem][data-admin--section-layout-param]", count: 6
    # Opening focuses the first choice; two steps down is "Three columns".
    page.driver.browser.keyboard.type(:down, :down, :enter)

    assert_selector "#section-#{@section.id}-lanes [data-admin--blocks-target='lane']", count: 3
    assert_no_selector "#{section_card} [role=menu]"
    assert_selector "#block-#{@section.id}-save-status", text: "SAVED"
    assert_writes_settled
    assert_eventually(message: "the focus is not on the Layout button the answer brought") { focus_is_on(layout_button) }
    assert_equal "three", @section.reload.settings["layout"]
  end

  test "choosing the layout the section already has sends nothing" do
    open_editor
    count_writes
    find(layout_button).click
    find("button[data-admin--section-layout-param='two']").click

    assert_no_selector "#{section_card} [role=menu]"
    await_frames
    assert_writes_settled
    assert_equal [], page.evaluate_script("window.__writes")
    assert_equal true, focus_is_on(layout_button)
  end

  test "a layout chosen in a tab that is behind is refused as changed elsewhere, and nothing is folded" do
    open_editor
    backdate(@section, by: 1.minute)
    as(users(:two), channel: :admin) { assert ContentBlocks::Save.call(ContentBlock.find(@section.id), attributes: { settings: { "background" => "tinted" } }).ok? }

    find(layout_button).click
    find("button[data-admin--section-layout-param='one']").click

    assert_selector "#block-#{@section.id}-save-status", text: "CHANGED ELSEWHERE"
    assert_selector "#section-#{@section.id}-lanes [data-admin--blocks-target='lane']", count: 2
    assert_equal 2, @right.reload.section_column
    assert_equal "two", @section.reload.settings["layout"]
  end

  test "background and width are saved from the header" do
    open_editor

    select "Tinted", from: "block-#{@section.id}-background"
    select "Full width", from: "block-#{@section.id}-width"
    page.execute_script("document.activeElement.blur()")

    assert_selector "#block-#{@section.id}-save-status", text: "SAVED"
    assert_equal %w[tinted full], @section.reload.settings.values_at("background", "width")
  end

  # Only a save that changed the number of columns redraws the lanes: the
  # tiles in them may be in use (an open menu, the focus, a drag).
  test "saving the background leaves the lanes' elements in place" do
    open_editor
    page.execute_script("document.getElementById(#{"section-#{@section.id}-lanes".to_json}).dataset.mark = 'kept'")

    select "Strong", from: "block-#{@section.id}-background"
    page.execute_script("document.activeElement.blur()")

    assert_selector "#block-#{@section.id}-save-status", text: "SAVED"
    assert_writes_settled
    assert_selector "#section-#{@section.id}-lanes[data-mark='kept']"
  end

  # The layout menu is replaced only by a save that changed the layout. A
  # save of the background would otherwise take the menu away under whoever
  # went on to it: by keyboard the focused button is replaced and the focus
  # falls to <body>; by pointer the menu just opened is swapped for a closed
  # one.
  test "a background save leaves the layout menu alone: Shift+Tab onto its button keeps the focus there" do
    open_editor
    page.execute_script("document.getElementById(#{"section-#{@section.id}-layout-menu".to_json}).dataset.mark = 'kept'")

    select "Tinted", from: "block-#{@section.id}-background"
    # Leaving the select for the Layout button is what sends the save.
    page.execute_script("document.querySelector(#{layout_button.to_json}).focus()")

    assert_selector "#block-#{@section.id}-save-status", text: "SAVED"
    assert_writes_settled
    await_frames
    assert_equal "tinted", @section.reload.settings["background"]
    assert_selector "#section-#{@section.id}-layout-menu[data-mark='kept']"
    assert_equal true, focus_is_on(layout_button)
  end

  test "a background save that lands while the layout menu is open leaves it open" do
    open_editor

    select "Tinted", from: "block-#{@section.id}-background"
    find(layout_button).click
    assert_selector "#{section_card} [role=menu] [role=menuitem][data-admin--section-layout-param]", count: 6

    assert_selector "#block-#{@section.id}-save-status", text: "SAVED"
    assert_writes_settled
    await_frames
    assert_equal "tinted", @section.reload.settings["background"]
    assert_selector "#{section_card} [role=menu] [role=menuitem][data-admin--section-layout-param]", count: 6
    assert_selector "#{layout_button}[aria-expanded='true']"
  end

  # A layout save that was refused leaves the form holding the layout that
  # was picked and the menu showing the one the section has. Picking it
  # again is asking again, not "no change".
  test "picking a layout again after its save was refused sends it again" do
    open_editor
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.__writes = 0
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() === "GET") return originalFetch(url, options)
        window.__writes += 1
        if (window.__writes > 1) return originalFetch(url, options)
        return Promise.resolve(new Response("", { status: 422, headers: { "Content-Type": "text/vnd.turbo-stream.html" } }))
      }
    JS

    find(layout_button).click
    find("button[data-admin--section-layout-param='one']").click
    # Not `assert_writes_settled`: a form whose save failed is not settled.
    assert_eventually(message: "the layout was never sent") { page.evaluate_script("window.__writes") == 1 }
    assert_no_selector "#{section_card} [role=menu]"
    assert_equal "two", @section.reload.settings["layout"]

    # The pick alone, with the menu closed: opening the menu moves the focus
    # inside the form, and a form whose save failed sends again on that by
    # itself -- which is not the rule this is about.
    page.execute_script("document.querySelector(#{"#{section_card} button[data-admin--section-layout-param='one']".to_json}).click()")

    assert_selector "#section-#{@section.id}-lanes [data-admin--blocks-target='lane']", count: 1
    assert_writes_settled
    assert_equal 2, page.evaluate_script("window.__writes")
    assert_equal "one", @section.reload.settings["layout"]
  end

  test "Remove section, keep blocks turns the tiles into cards in reading order" do
    open_editor
    find("##{ActionView::RecordIdentifier.dom_id(@section)} button[aria-label='Section actions']").click
    press "Remove section, keep blocks"

    assert_no_selector ".admin-section-card"
    assert_equal [ @left.id, @right.id ], page.all("#content-blocks-list > .admin-block-card").map { |card| card["data-block-id"].to_i }
    assert_empty @page.content_blocks.where(block_type: "section")
  end

  # The cards that take the section's place are cards like any other: each
  # autosaves on its own base, and the list's first and last are told so.
  test "a block kept from a removed section is edited as a card, and the list's ends are marked" do
    open_editor
    find("#{section_card} button[aria-label='Section actions']").click
    press "Remove section, keep blocks"
    assert_selector "#content-blocks-list > .admin-block-card", count: 2

    fill_in id: caption(@right), with: "Typed in the card"
    page.execute_script("document.activeElement.blur()")

    assert_selector "#block-#{@right.id}-save-status", text: "SAVED"
    assert_no_text "CHANGED ELSEWHERE"
    assert_equal "Typed in the card", @right.reload.caption
    assert_selector "#{tile(@left)} button[data-move='up'][disabled]", visible: :all
    assert_selector "#{tile(@right)} button[data-move='down'][disabled]", visible: :all
    assert_selector "#{tile(@left)} button[data-move='down']:not([disabled])", visible: :all
  end

  # "Remove section, keep blocks" is the one action of a section that replaces
  # the forms of blocks that STAY: its answer draws a card for each in the
  # section's place. So it runs only on a settled screen (`admin--queue-hold`
  # on its form): a form paused by a 409 holds text that is nowhere else, and
  # the bar over it has promised that it is still there.
  test "Remove section, keep blocks does not run while a form holds text that was refused, and says so" do
    open_editor
    find(face(@left)).click
    travel 1.minute do
      as(users(:two), channel: :admin) { ContentBlocks::Save.call(@left, translations: { "en" => { caption: "Theirs" } }) }
    end
    fill_in id: caption(@left), with: "Mine, refused"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE", wait: 8
    count_writes

    find("#{section_card} button[aria-label='Section actions']").click
    press "Remove section, keep blocks"

    assert_selector "#toasts #toast-queue-hold[role=alert]", text: "Your last change wasn't saved, so this didn't run."
    assert_selector section_card
    assert_equal [ @left.id ], tiles_in(1)
    assert_field caption(@left), with: "Mine, refused"
    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE"
    assert_equal @section.id, @left.reload.section_id
    assert_equal "Theirs", @left.caption
    await_frames # a delete sent after all would have called fetch by now: the toast is shown after the drain that would have sent it
    assert_equal [], page.evaluate_script("window.__writes"), "the section's removal was sent"
  end

  # The other half: nothing is unclean, but a save of a form in the section is
  # on the wire and more was typed behind it. The removal waits for the queue
  # to be EMPTY, not for its turn in it -- in its turn it would go before that
  # save's follow-up, and its answer would take the form with the words.
  test "Remove section, keep blocks waits for an edit typed while the block's save was on the wire" do
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

    find("#{section_card} button[aria-label='Section actions']").click
    press "Remove section, keep blocks"
    page.execute_script("window.__release[0]()")

    assert_no_selector ".admin-section-card"
    assert_writes_settled
    assert_equal [ @left.id, @right.id ], cards_in_list
    assert_equal "Second, typed behind it", @left.reload.caption
    assert_field caption(@left), with: "Second, typed behind it"
    assert_nil @left.section_id
    assert_empty @page.content_blocks.where(block_type: "section")
    writes = page.evaluate_script("window.__writes")
    assert_equal 3, writes.size, "the two saves and the removal"
    assert writes.last.end_with?("/content_blocks/#{@section.id}"), "the removal went before the save it had to wait for: #{writes.inspect}"
    assert_no_selector "#toasts #toast-queue-hold"
  end

  test "Delete section and its blocks asks first, naming how many blocks go with it" do
    open_editor
    find("##{ActionView::RecordIdentifier.dom_id(@section)} button[aria-label='Section actions']").click
    press "Delete section and its blocks…"

    assert_selector "dialog[open]", text: "This also deletes the 2 blocks in it."
    within("dialog[open]") { press "Delete section" }

    assert_no_selector ".admin-section-card"
    assert_empty @page.content_blocks.reload
  end

  test "Cancel in the delete dialog deletes nothing, and the dialog counts the blocks as they are after one was deleted" do
    gone = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    gone.update_column(:block_type, "gone/thing")
    open_editor
    find(face(gone)).click
    within(panel(gone)) { press "Delete block…" }
    within("dialog[open]") { press "Delete block" }
    assert_no_selector tile(gone)

    find("#{section_card} button[aria-label='Section actions']").click
    press "Delete section and its blocks…"

    assert_selector "dialog[open]", text: "This also deletes the 2 blocks in it."
    within("dialog[open]") { press "Cancel" }
    assert_no_selector "dialog[open]"
    assert_selector ".admin-section-card"
    assert_equal 3, @page.content_blocks.reload.size
  end

  test "the section's menu moves it among the cards and duplicates it with its blocks" do
    above = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @section.update_column(:position, 1)
    open_editor
    assert_equal [ above.id, @section.id ], page.all("#content-blocks-list > .admin-block-card").map { |card| card["data-block-id"].to_i }

    find("#{section_card} button[aria-label='Section actions']").click
    press "Move up"

    assert_selector "#content-blocks-status", text: "SAVED"
    assert_equal [ @section.id, above.id ], @page.content_blocks.top_level.reorder(:position).ids

    find("#{section_card} button[aria-label='Section actions']").click
    press "Duplicate"

    assert_selector ".admin-section-card", count: 2
    copy = @page.content_blocks.top_level.reorder(:position).second
    assert copy.container?
    assert_selector "##{ActionView::RecordIdentifier.dom_id(copy)} .admin-block-tile", count: 2
    assert_equal 2, copy.section_blocks.size
  end

  test "the section's name collapses it to one line" do
    open_editor
    find("##{ActionView::RecordIdentifier.dom_id(@section)} button[aria-expanded]", text: "Section").click

    assert_no_selector "#section-#{@section.id}-lanes"
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 2 blocks"
  end

  # Carried from the lane picker's review. The form of a block another tab
  # folded out of its column is open here; the refused add redraws the lanes,
  # and with them what names a column: that form's heading and the header's
  # count. The form itself is never replaced. And the "+" that was pressed is
  # gone with its lane, so the focus goes to the "+" of the last lane there
  # is -- the column the removed ones were folded into -- not to <body>.
  test "a refused add brings the open form's heading and the count up to date, and the focus goes to the last lane's +" do
    @section.update!(settings: @section.settings.merge("layout" => "four"))
    far = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 4, position: 0)
    open_editor
    find(face(far)).click
    assert_selector panel(far), text: "Image · column 4"
    page.execute_script("document.getElementById(#{"block-#{far.id}-panel".to_json}).dataset.mark = 'kept'")
    as(users(:two), channel: :admin) { assert ContentBlocks::Save.call(ContentBlock.find(@section.id), attributes: { settings: { "layout" => "two" } }).ok? }

    find("#block-picker-#{@section.id}-4 button[aria-haspopup=menu]").click
    within("#block-picker-#{@section.id}-4") { press "Image" }

    assert_selector "#content-blocks-alert", text: "isn't a column of this section"
    assert_selector "#{panel(far)}[data-mark='kept']", text: "Image · column 2"
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 3 blocks", exact_text: true
    assert_selector "#{face(far)}[aria-expanded='true']"
    assert_eventually(message: "the focus is not on the last lane's +") { focus_is_on("#block-picker-#{@section.id}-2 button[aria-haspopup=menu]") }
  end

  test "a collapsed section is its one header line, and expands to its lanes again" do
    open_editor
    # Inside the card: the "Add block" row has a "Section" button of its own.
    within(tile(@section)) { press "Section" }

    assert_no_selector "#section-#{@section.id}-lanes"
    assert_selector "#{tile(@section)} > div:first-child", text: /Section\s·\s2 columns · 2 blocks/

    within(tile(@section)) { press "Section" }

    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile"
  end

  test "a page without sections has its cards, no section card and no section controller" do
    plain = create_page(title: "Plain")
    plain.content_blocks.create!(block_type: "rich_text", position: 0)
    visit "/cs-studio/pages/#{plain.id}"
    await_admin_controllers

    assert_selector "#content-blocks-list > .admin-block-card", count: 1
    assert_no_selector ".admin-section-card"
    assert_no_selector "[data-controller~='admin--section']"
  end

  # ---- Moving by drag (sections spec §4.4; plan D8, D9) ----
  #
  # A drop is driven the way `blocks_test.rb`'s "dragging a block's handle
  # reorders the list" drives it: the element is moved in the DOM as a drop
  # leaves it, then the controller's own sender is called, which is the code a
  # drop's `onEnd` runs. That makes a test independent of how fast SortableJS
  # samples the pointer; the tests named "the pointer ..." use the pointer for
  # real, and are what holds the Sortables' own wiring (handle, group, `put`).

  def blocks_controller = "window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller~=\"admin--blocks\"]'), 'admin--blocks')"

  # Moves `block`'s element to the end of `target` (a CSS selector of a lane or
  # the list), or to its start, and sends it, as a drop there does.
  def drop_into(block, target, at: :end)
    page.execute_script(<<~JS)
      const controller = #{blocks_controller}
      const item = document.querySelector('[data-block-id="#{block.id}"]:not([data-admin--section-target="panel"])')
      const from = item.parentElement
      const before = controller.snapshot()
      document.querySelector(#{target.to_json}).#{at == :start ? "prepend" : "append"}(item)
      controller.move(item, from, before)
    JS
  end

  # Every write this page sends from now on is answered as `plan` says, by its
  # number: "hold" keeps it until `window.__release[n]()` -- which then lets it
  # through, or answers for it with `window.__release[n]("fail")` -- "fail"
  # answers with an error page at once, and anything past the plan's end goes
  # through. `window.__writes` lists them.
  def script_writes(*plan)
    page.execute_script(<<~JS, plan)
      const plan = arguments[0]
      const originalFetch = window.fetch
      const failure = () => new Response("<h1>Bad gateway</h1>", { status: 502, headers: { "Content-Type": "text/html" } })
      window.__writes = []
      window.__release = []
      window.fetch = (url, options = {}) => {
        if ((options.method || "GET").toUpperCase() === "GET") return originalFetch(url, options)
        const number = window.__writes.push(String(url.url || url)) - 1
        if (plan[number] === "fail") return Promise.resolve(failure())
        if (plan[number] !== "hold") return originalFetch(url, options)
        return new Promise((resolve) => { window.__release[number] = (how) => resolve(how === "fail" ? failure() : originalFetch(url, options)) })
      }
    JS
  end

  def lane(column, section = @section) = "#section-#{section.id}-lane-#{column}"
  def tiles_in(column, section = @section) = page.all("#{lane(column, section)} > [data-block-id]").map { |tile| tile["data-block-id"].to_i }
  def cards_in_list = page.all("#content-blocks-list > [data-block-id]").map { |card| card["data-block-id"].to_i }

  def assert_order_eventually(expected)
    seen = nil
    assert_eventually(message: -> { "the order never read #{expected.inspect} (last seen #{seen.inspect})" }) do
      seen = yield
      seen == expected
    end
  end

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
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 2 blocks"
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

    assert_selector "#content-blocks-list > .admin-block-card[data-block-id='#{@left.id}'] form[data-controller~='admin--autosave']"
    assert_no_selector panel(@left), visible: :all
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 1 block"
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
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 3 blocks"
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
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 1 block"
    assert_selector "#section-#{other.id}-summary", text: "2 columns · 1 block"
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
      as(users(:two), channel: :admin) { ContentBlocks::Save.call(@left, translations: { "en" => { caption: "Theirs" } }) }
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
    as(users(:two), channel: :admin) { assert ContentBlocks::Save.call(ContentBlock.find(@section.id), attributes: { settings: { "layout" => "one" } }).ok? }
    # An edit in another block's form, still inside its debounce: the list
    # that the refusal brings replaces that form.
    page.execute_script(<<~JS)
      const field = document.getElementById(#{caption(card).to_json})
      field.value = "Typed in a card, not sent yet"
      field.dispatchEvent(new Event("input", { bubbles: true }))
    JS

    drop_into(@left, lane(2))

    assert_selector "#content-blocks-alert", text: "That section or column no longer exists"
    assert_selector "#section-#{@section.id}-lanes [data-admin--blocks-target='lane']", count: 1
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
      as(users(:two), channel: :admin) { ContentBlocks::Save.call(@right, translations: { "en" => { caption: "Theirs" } }) }
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
    as(users(:two), channel: :admin) { assert ContentBlocks::Save.call(ContentBlock.find(@section.id), attributes: { settings: { "layout" => "one" } }).ok? }
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
  # (`admin--blocks#besideSection`): before it from its header, after it from
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
        const lanes = section.querySelector('[data-admin--section-target="lanes"]').getBoundingClientRect()
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

  # ---- The pointer ----

  def centre(selector)
    page.evaluate_script("(() => { const r = document.querySelector(arguments[0]).getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2] })()", selector)
  end

  # Where a drag onto `selector` is aimed: low in it, never its middle.
  # SortableJS puts an element that comes from another container before or
  # after the one under the pointer by the half the pointer is in, and at the
  # exact middle it does neither.
  def drop_point(selector)
    page.evaluate_script("(() => { const r = document.querySelector(arguments[0]).getBoundingClientRect(); return [r.left + r.width / 2, r.bottom - 8] })()", selector)
  end

  # Presses on `grip` and walks the pointer to `target` (see `drag_pointer`);
  # the caller waits for the slot it expects and releases.
  def drag_to(grip, target)
    page.execute_script("document.querySelector('#content-blocks-list').scrollIntoView({ block: 'center' })")
    from_x, from_y = centre(grip)
    to_x, to_y = drop_point(target)
    assert_operator [ from_y, to_y ].max, :<, page.evaluate_script("window.innerHeight"), "both ends of the drag are on screen"
    assert_operator [ from_y, to_y ].min, :>, 0, "both ends of the drag are on screen"

    drag_pointer(from_x, from_y, to_y, to_x: to_x)
  end

  def slot_in(container) = "!!document.querySelector(#{"#{container} > .admin-drag-ghost".to_json})"

  test "the pointer drags a tile from one lane to the other" do
    open_editor

    mouse = drag_to("#{tile(@left)} .admin-block-tile__grip", lane(2))
    assert_selector "body > .admin-drag-fallback"
    assert_no_selector "body > .admin-drag-fallback[id], body > .admin-drag-fallback [id]", visible: :all
    await_js slot_in(lane(2))
    mouse.up

    assert_eventually { @left.reload.section_column == 2 }
    assert_writes_settled
    assert_no_selector ".admin-drag-fallback"
    assert_equal [ @right.id, @left.id ], tiles_in(2)
    assert_equal [ @right.id, @left.id ], @page.content_blocks.in_column(@section, 2).reorder(:position).ids
    assert_empty tiles_in(1)
  end

  test "the pointer drags a card into an empty lane, where it becomes a tile" do
    @right.destroy!
    card = @page.content_blocks.create!(block_type: "post_list", position: 1)
    open_editor

    mouse = drag_to("#{tile(card)} .admin-block-card__handle", lane(2))
    await_js slot_in(lane(2))
    mouse.up

    assert_selector "#{lane(2)} > .admin-block-tile[data-block-id='#{card.id}']"
    assert_equal [ @section.id, 2 ], card.reload.then { |b| [ b.section_id, b.section_column ] }
    assert_equal [ @section.id ], cards_in_list
  end

  test "the pointer drags a tile out of its section into the page's list, where it becomes a card" do
    below = @page.content_blocks.create!(block_type: "post_list", position: 1)
    open_editor

    mouse = drag_to("#{tile(@left)} .admin-block-tile__grip", "#{tile(below)} .admin-block-card__handle")
    await_js slot_in("#content-blocks-list")
    mouse.up

    assert_selector "#content-blocks-list > .admin-block-card[data-block-id='#{@left.id}']"
    assert_nil @left.reload.section_id
    assert_equal [ @section.id, below.id, @left.id ].sort, @page.content_blocks.top_level.ids.sort
    assert_writes_settled
    assert_equal @page.content_blocks.top_level.reorder(:position).ids, cards_in_list
  end

  # A section's card dragged over another section: its lanes refuse it (a
  # section never holds a section), and the list takes it as it takes any
  # card. And the drag is seen through: every lane of the dragged card is
  # disconnected and connected again each time the card moves in the list, and
  # a Sortable destroyed then would end the drag where it was.
  test "the pointer drags a section's card past another section and a card, to the end of the list" do
    other = @page.content_blocks.create!(block_type: "section", position: 1)
    inside = @page.content_blocks.create!(block_type: "image", section: other, section_column: 1, position: 0)
    last = @page.content_blocks.create!(block_type: "image", position: 2)
    open_editor

    mouse = drag_to("#{tile(@section)} > div:first-child .admin-block-card__handle", tile(last))
    await_drag_slot "#content-blocks-list > .admin-drag-ghost", at: :last
    assert_no_selector "#{lane(1, other)} > .admin-drag-ghost, #{lane(2, other)} > .admin-drag-ghost", visible: :all
    mouse.up

    assert_eventually { @page.content_blocks.top_level.reorder(:position).ids == [ other.id, last.id, @section.id ] }
    assert_writes_settled
    assert_equal [ other.id, last.id, @section.id ], cards_in_list
    assert_equal [ other.id, 1 ], inside.reload.then { |b| [ b.section_id, b.section_column ] }
    assert_equal @section.id, @left.reload.section_id

    # The lanes that travelled with the card still take a drop.
    mouse = drag_to("#{tile(@left)} .admin-block-tile__grip", lane(2))
    await_js slot_in(lane(2))
    mouse.up
    assert_eventually { @left.reload.section_column == 2 }
    assert_writes_settled
  end

  # ---- Every move from the menu, by keyboard (sections spec §1, §4.4) -------
  #
  # A tile's grip is for the pointer, so its "⋯" menu is the only way a
  # keyboard user moves a block that is in a section; a top-level card's menu
  # is how one gets into a section without a drag. These tests work the menus
  # with keys alone -- the button is focused by script, because `send_keys` on
  # an element clicks it first, which would be the pointer opening the menu --
  # and each says where the focus is afterwards: never on <body>.

  def keyboard = page.driver.browser.keyboard
  def menu_button(scope) = "#{scope} button[aria-label='Block actions']"
  def focused_text = page.evaluate_script("document.activeElement?.textContent.trim()")
  def card(block) = "#content-blocks-list > .admin-block-card[data-block-id='#{block.id}']"

  # Opens the block's "⋯" with Enter, walks down to the item and presses Enter
  # on it. Opening puts the focus on the first item that is not disabled.
  def pick_by_keyboard(scope, label)
    page.execute_script("document.querySelector(#{menu_button(scope).to_json}).focus()")
    keyboard.type(:enter)
    assert_selector "#{scope} [role=menu]"
    8.times do
      break if focused_text == label

      keyboard.type(:down)
    end
    assert_equal label, focused_text, "the menu has no item #{label.inspect} the arrow keys reach"
    keyboard.type(:enter)
  end

  def assert_focus_on(selector, what)
    assert_eventually(message: -> { "the focus is not on #{what}, but on #{page.evaluate_script("document.activeElement?.outerHTML.slice(0, 160)")}" }) { focus_is_on(selector) }
  end

  test "Move down and Move up reorder a lane from the keyboard, and the focus stays on the tile's menu" do
    below = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 1)
    open_editor
    assert_selector "#{tile(@left)} button[data-move='up'][disabled]", visible: :all

    pick_by_keyboard(tile(@left), "Move down")

    assert_eventually { @page.content_blocks.in_column(@section, 1).reorder(:position).ids == [ below.id, @left.id ] }
    assert_equal [ below.id, @left.id ], tiles_in(1)
    assert_selector "#{tile(@left)} button[data-move='down'][disabled]", visible: :all
    assert_selector "#{tile(below)} button[data-move='up'][disabled]", visible: :all
    assert_no_selector "#{tile(@left)} [role=menu]"
    assert_focus_on menu_button(tile(@left)), "the moved tile's menu"
    assert_no_selector "#toasts .admin-toast", text: "Undo"

    pick_by_keyboard(tile(@left), "Move up")

    assert_eventually { @page.content_blocks.in_column(@section, 1).reorder(:position).ids == [ @left.id, below.id ] }
    assert_focus_on menu_button(tile(@left)), "the moved tile's menu"
    assert_writes_settled
  end

  # Along one lane nothing is redrawn and nothing held, so the focus is on the
  # tile's menu as soon as the tile has moved, not only once the answer is in.
  test "a tile moved along its lane has the focus at once, while its move is still on the wire" do
    below = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 1)
    open_editor
    script_writes("hold")

    pick_by_keyboard(tile(@left), "Move down")

    await_js "window.__release.length === 1"
    assert_equal [ below.id, @left.id ], tiles_in(1)
    assert focus_is_on(menu_button(tile(@left))), "the focus is not on the moved tile's menu while its move is out"
    assert_no_selector "#{tile(@left)} [role=menu]"

    page.execute_script("window.__release[0]()")
    assert_writes_settled
    assert_equal [ below.id, @left.id ], @page.content_blocks.in_column(@section, 1).reorder(:position).ids
    assert focus_is_on(menu_button(tile(@left)))
  end

  # By keys alone, the dialog included: Enter on the item opens it with the
  # focus on the select, which holds the one other column; Tab, Tab is Move.
  test "Move to column… moves a tile to the end of the chosen lane, and the focus follows it" do
    open_editor

    pick_by_keyboard(tile(@left), "Move to column…")
    assert_selector "#move-block-dialog[open]"
    assert_equal [ "Column 2" ], page.all("#move-block-destination option").map(&:text)
    assert_focus_on "#move-block-destination", "the dialog's select"
    keyboard.type(:tab, :tab)
    assert_equal "Move", focused_text
    keyboard.type(:enter)

    assert_no_selector "#move-block-dialog[open]"
    assert_eventually { @left.reload.section_column == 2 }
    assert_equal [ @right.id, @left.id ], @page.content_blocks.in_column(@section, 2).reorder(:position).ids
    assert_selector "#{lane(2)} > .admin-block-tile", count: 2
    assert_equal [ @right.id, @left.id ], tiles_in(2)
    assert_writes_settled
    assert_focus_on menu_button(tile(@left)), "the moved tile's menu"
    # Its form says the new column, and is still the one form the block has.
    find(face(@left)).click
    assert_selector panel(@left), text: "Image · column 2"
    assert_selector "[id='block-#{@left.id}-panel']", count: 1, visible: :all
  end

  test "Escape in the Move dialog moves nothing and gives the focus back to the tile's menu" do
    open_editor
    count_writes

    pick_by_keyboard(tile(@left), "Move to column…")
    assert_focus_on "#move-block-destination", "the dialog's select"
    keyboard.type(:escape)

    assert_no_selector "#move-block-dialog[open]"
    assert_focus_on menu_button(tile(@left)), "the tile's menu"
    assert_equal [ @left.id ], tiles_in(1)
    await_frames # a move would have been queued and sent by Move's own click
    assert_equal [], page.evaluate_script("window.__writes")
  end

  test "Move to column… is disabled in a section of one column, and enabled again by a second" do
    @section.update!(settings: { "layout" => "one" })
    @right.update_columns(section_column: 1, position: 1)
    open_editor
    assert_selector "#{tile(@left)} button[data-move='column'][disabled]", visible: :all
    assert_selector "#{tile(@right)} button[data-move='column'][disabled]", visible: :all

    find(layout_button).click
    find("#{section_card} [role=menuitem][data-admin--section-layout-param='two']").click

    assert_selector "#section-#{@section.id}-lanes [data-admin--blocks-target='lane']", count: 2
    assert_selector "#{tile(@left)} button[data-move='column']:not([disabled])", visible: :all
    assert_writes_settled
  end

  test "Move out of section puts the block right after the section as a card, with the focus on it" do
    last = @page.content_blocks.create!(block_type: "image", position: 1)
    open_editor

    pick_by_keyboard(tile(@left), "Move out of section")

    assert_selector card(@left)
    assert_writes_settled
    assert_equal [ @section.id, @left.id, last.id ], @page.content_blocks.top_level.reorder(:position).ids
    assert_equal [ @section.id, @left.id, last.id ], cards_in_list
    assert_nil @left.reload.section_id
    assert_no_selector panel(@left), visible: :all
    assert_selector "#section-#{@section.id}-summary", text: "1 block"
    assert_focus_on "#{card(@left)} .admin-block-card__handle", "the handle of the card the block became"
    # One delete dialog for the block: the tile's went with the tile.
    assert_selector "[id='delete-block-#{@left.id}']", count: 1, visible: :all
    assert_no_selector "#toasts .admin-toast", text: "Undo"
  end

  test "Move into section… offers every column of every section, and is disabled without one" do
    block = @page.content_blocks.create!(block_type: "image", position: 1)
    second = @page.content_blocks.create!(block_type: "section", position: 2, settings: { "layout" => "three" })
    open_editor
    scope = "##{ActionView::RecordIdentifier.dom_id(block)}"

    pick_by_keyboard(scope, "Move into section…")
    within("#move-block-dialog") do
      assert_equal [ "Section 1 · column 1", "Section 1 · column 2", "Section 2 · column 1", "Section 2 · column 2", "Section 2 · column 3" ],
        page.all("option").map(&:text)
      select "Section 2 · column 3", from: "move-block-destination"
    end
    page.execute_script("document.querySelector('#move-block-dialog button[data-action=\"admin--blocks#moveTo\"]').focus()")
    keyboard.type(:enter)

    assert_eventually { block.reload.then { |b| [ b.section_id, b.section_column ] } == [ second.id, 3 ] }
    assert_selector "#{lane(3, second)} > .admin-block-tile[data-block-id='#{block.id}']"
    assert_writes_settled
    assert_equal [ @section.id, second.id ], cards_in_list
    assert_selector "#section-#{second.id}-summary", text: "1 block"
    assert_focus_on menu_button("#{lane(3, second)} > .admin-block-tile"), "the menu of the tile the card became"
    # The tile it became opens its form, under the section it went into.
    find("#{lane(3, second)} .admin-block-tile__face").click
    assert_selector "#section-#{second.id}-panels > #block-#{block.id}-panel", text: "Image · column 3"

    plain = create_page(title: "No sections")
    plain.content_blocks.create!(block_type: "image", position: 0)
    visit "/cs-studio/pages/#{plain.id}"
    await_admin_controllers
    assert_selector "button[data-move='into'][disabled]", visible: :all
  end

  # A section's card is added and removed without the other cards being drawn
  # again, so it is the screen that says whether there is one to move into.
  test "Move into section… is enabled when the page gains a section and disabled when it loses its last" do
    plain = create_page(title: "Gains a section")
    block = plain.content_blocks.create!(block_type: "image", position: 0)
    visit "/cs-studio/pages/#{plain.id}"
    await_admin_controllers
    scope = "##{ActionView::RecordIdentifier.dom_id(block)}"
    assert_selector "#{scope} button[data-move='into'][disabled]", visible: :all

    within("#block-picker-end") { press "Section" }

    assert_selector ".admin-section-card [data-admin--blocks-target='lane']", count: 2
    assert_selector "#{scope} button[data-move='into']:not([disabled])", visible: :all
    assert_writes_settled

    find(".admin-section-card button[aria-label='Section actions']").click
    press "Delete section and its blocks…"
    within("dialog[open]") { press "Delete section" }

    assert_no_selector ".admin-section-card"
    assert_selector "#{scope} button[data-move='into'][disabled]", visible: :all
    assert_writes_settled
  end

  # A collapsed section shows one line: a block moved into it would be gone
  # from the screen, and nothing would be left to take the focus.
  test "a block moved into a collapsed section opens the section" do
    block = @page.content_blocks.create!(block_type: "image", position: 1)
    open_editor
    find("#{section_card} button[aria-expanded]", text: "Section").click
    assert_no_selector lane(1)
    scope = "##{ActionView::RecordIdentifier.dom_id(block)}"

    pick_by_keyboard(scope, "Move into section…")
    within("#move-block-dialog") { select "Section 1 · column 2", from: "move-block-destination" }
    page.execute_script("document.querySelector('#move-block-dialog button[data-action=\"admin--blocks#moveTo\"]').focus()")
    keyboard.type(:enter)

    assert_selector "#{lane(2)} > .admin-block-tile[data-block-id='#{block.id}']"
    assert_selector "#{section_card} button[aria-expanded='true']", text: "Section"
    assert_writes_settled
    assert_equal [ @section.id, 2 ], block.reload.then { |b| [ b.section_id, b.section_column ] }
    assert_focus_on menu_button("#{lane(2)} > .admin-block-tile[data-block-id='#{block.id}']"), "the menu of the tile the card became"
  end

  # Review gap 2: the copy of a block in a column is drawn in that column,
  # after its source. Not opened (see `copy_tile_streams`): the form that was
  # open stays open.
  test "Duplicate from a tile's menu puts the copy's tile after its source, unopened, with the focus on its menu" do
    below = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 1)
    open_editor
    find(face(@right)).click
    assert_selector panel(@right)

    pick_by_keyboard(tile(@left), "Duplicate")

    assert_selector "#{lane(1)} > .admin-block-tile", count: 3
    assert_writes_settled
    copy = (@page.content_blocks.in_column(@section, 1).to_a - [ @left, below ]).sole
    assert_equal [ @left.id, copy.id, below.id ], @page.content_blocks.in_column(@section, 1).reorder(:position).ids
    assert_equal [ @left.id, copy.id, below.id ], tiles_in(1)
    assert_equal [ @section.id ], cards_in_list
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 4 blocks", exact_text: true
    assert_selector "#section-#{@section.id}-panels > #{panel(copy)}", visible: :all
    assert_no_selector panel(copy)
    assert_selector panel(@right)
    assert_focus_on menu_button(tile(copy)), "the copy's menu"
    assert_selector "#{tile(copy)} button[data-move='up']:not([disabled])", visible: :all

    # The copy is a block like any: its form opens and saves on its own base.
    find(face(copy)).click
    fill_in id: caption(copy), with: "The copy's own caption"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{copy.id}-save-status", text: "SAVED"
    assert_writes_settled
    assert_equal [ "The copy's own caption", nil ], [ copy.reload.caption, @left.reload.caption ]
  end

  # Review gap 1: the delete dialog is the tile's, so it opens while the
  # block's form -- the hidden panel it used to be in -- is closed.
  test "Delete block… from a tile's menu asks and deletes with the block's form closed, and leaves no dialog behind" do
    open_editor
    assert_no_selector panel(@left)

    pick_by_keyboard(tile(@left), "Delete block…")
    assert_selector "#delete-block-#{@left.id}[open]", text: "Delete this block?"
    assert_equal "Cancel", focused_text
    keyboard.type(:enter)

    assert_no_selector "dialog[open]"
    assert_selector tile(@left)
    assert_focus_on menu_button(tile(@left)), "the tile's menu, after Cancel"
    assert ContentBlock.exists?(@left.id)

    pick_by_keyboard(tile(@left), "Delete block…")
    keyboard.type(:tab)
    assert_equal "Delete block", focused_text
    keyboard.type(:enter)

    assert_no_selector tile(@left)
    assert_no_selector panel(@left), visible: :all
    assert_no_selector "[id='delete-block-#{@left.id}']", visible: :all
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 1 block", exact_text: true
    assert_writes_settled
    assert_not ContentBlock.exists?(@left.id)
  end

  # The dialog travels with the element that stands for the block: the card a
  # tile becomes has its own, and the tile's is gone with the tile.
  test "a block moved out of its section is deleted from its card's menu, through the card's own dialog" do
    open_editor
    pick_by_keyboard(tile(@left), "Move out of section")
    assert_selector card(@left)
    assert_writes_settled

    pick_by_keyboard(card(@left), "Delete block…")
    assert_selector "#{card(@left)} #delete-block-#{@left.id}[open]"
    within("dialog[open]") { press "Delete block" }

    assert_no_selector "[data-block-id='#{@left.id}']", visible: :all
    assert_no_selector "[id='delete-block-#{@left.id}']", visible: :all
    assert_writes_settled
    assert_not ContentBlock.exists?(@left.id)
  end

  # Review gap 3, the refusals. A menu's move that fails is put back like a
  # drop that fails, and the focus goes back with the block.
  test "a menu move that never reaches the server puts the tile back with the focus on its menu" do
    open_editor
    script_writes("fail")

    pick_by_keyboard(tile(@left), "Move out of section")

    assert_selector "#toasts .admin-toast[role=alert]", text: "Couldn't save the new order. Check your connection and try again."
    assert_order_eventually([ @left.id ]) { tiles_in(1) }
    assert_equal [ @section.id ], cards_in_list
    assert_writes_settled
    assert_equal @section.id, @left.reload.section_id
    assert_focus_on menu_button(tile(@left)), "the menu of the tile that was put back"
    assert_not page.evaluate_script("document.querySelector(#{tile(@left).to_json}).inert"), "the tile was left held"
  end

  # The column was folded away in another tab: the refusal redraws the list,
  # and the tile that had the focus is no longer in the page. The block's new
  # tile takes it.
  test "a menu move into a column that is gone redraws the list and puts the focus on the block's new tile" do
    open_editor
    as(users(:two), channel: :admin) { assert ContentBlocks::Save.call(ContentBlock.find(@section.id), attributes: { settings: { "layout" => "one" } }).ok? }

    pick_by_keyboard(tile(@left), "Move to column…")
    assert_focus_on "#move-block-destination", "the dialog's select"
    keyboard.type(:tab, :tab, :enter)

    assert_selector "#content-blocks-alert", text: "That section or column no longer exists"
    assert_selector "#section-#{@section.id}-lanes [data-admin--blocks-target='lane']", count: 1
    assert_writes_settled
    assert_equal [ @left.id, @right.id ], tiles_in(1)
    assert_equal [ [ 1, 0 ], [ 1, 1 ] ], [ @left, @right ].map { |block| block.reload.then { |b| [ b.section_column, b.position ] } }
    assert_focus_on menu_button(tile(@left)), "the menu of the block's redrawn tile"
    assert_selector "#{tile(@left)} button[data-move='column'][disabled]", visible: :all
  end

  # A block whose form holds a refused save is not moved by a drop
  # (`admin--blocks#move`), and not by the menu either: the same sender.
  test "a block whose form was refused is not moved from the menu: it stays, with its text, and takes the focus back" do
    open_editor
    find(face(@left)).click
    travel 1.minute do
      as(users(:two), channel: :admin) { ContentBlocks::Save.call(@left, translations: { "en" => { caption: "The other editor's caption" } }) }
    end
    fill_in id: caption(@left), with: "Mine, refused"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE", wait: 8

    pick_by_keyboard(tile(@left), "Move out of section")

    assert_selector "#toasts .admin-toast[role=alert]", text: "Reload or fix this block before moving it."
    assert_order_eventually([ @left.id ]) { tiles_in(1) }
    assert_equal [ @section.id ], cards_in_list
    assert_field caption(@left), with: "Mine, refused"
    assert_equal @section.id, @left.reload.section_id
    assert_focus_on menu_button(tile(@left)), "the menu of the tile that was not moved"
  end

  # ---- Menu moves: an unavailable tile, what is announced, where the focus stays

  def announced = page.evaluate_script("document.querySelector('[data-admin--blocks-target=\"announcer\"]').textContent")

  # Spec §1: the grip moves an unavailable tile, so the menu does too.
  test "a tile of an unregistered type is moved along its lane and out of its section from the keyboard" do
    gone = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    gone.update_column(:block_type, "gone/thing")
    open_editor

    pick_by_keyboard(tile(gone), "Move up")

    assert_eventually { @page.content_blocks.in_column(@section, 1).reorder(:position).ids == [ gone.id, @left.id ] }
    assert_equal [ gone.id, @left.id ], tiles_in(1)
    assert_focus_on menu_button(tile(gone)), "the unavailable tile's menu"
    assert_writes_settled

    pick_by_keyboard(tile(gone), "Move out of section")

    assert_selector "#{card(gone)}.border-danger", text: "Unavailable type — gone/thing"
    assert_writes_settled
    assert_equal [ @section.id, gone.id ], @page.content_blocks.top_level.reorder(:position).ids
    assert_nil gone.reload.section_id
    assert_no_selector panel(gone), visible: :all
    assert_equal [ @left.id ], tiles_in(1)
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 2 blocks", exact_text: true
  end

  # The focus lands on a button every tile names the same, "Block actions":
  # what moved and where is said in the live region, as the handle's keyboard
  # path says it for a card.
  test "a menu move is announced: which block, and where it went" do
    below = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    open_editor

    pick_by_keyboard(tile(@left), "Move down")
    assert_equal "Image moved down. Position 2 of 2.", announced
    assert_eventually { @page.content_blocks.in_column(@section, 1).reorder(:position).ids == [ below.id, @left.id ] }

    pick_by_keyboard(tile(below), "Move to column…")
    assert_focus_on "#move-block-destination", "the dialog's select"
    keyboard.type(:tab, :tab, :enter)
    assert_equal "Rich text moved to column 2. Position 2 of 2.", announced
    assert_eventually { below.reload.section_column == 2 }
    assert_writes_settled

    pick_by_keyboard(tile(below), "Move out of section")
    assert_equal "Rich text moved out of the section. Position 2 of 2.", announced
    assert_selector card(below)
    assert_writes_settled

    pick_by_keyboard(card(below), "Move into section…")
    assert_focus_on "#move-block-destination", "the dialog's select"
    keyboard.type(:tab, :tab, :enter)
    assert_equal "Rich text moved to column 1 of section 1. Position 2 of 2.", announced
    assert_eventually { below.reload.section_column == 1 }
    assert_writes_settled
  end

  test "a menu move that fails is announced as put back" do
    open_editor
    script_writes("fail")

    pick_by_keyboard(tile(@left), "Move out of section")

    assert_selector "#toasts .admin-toast[role=alert]", text: "Couldn't save the new order."
    assert_order_eventually([ @left.id ]) { tiles_in(1) }
    assert_writes_settled
    assert_eventually { announced == "Image is back where it was." }
  end

  # A move along one container holds nothing and redraws nothing, so the end
  # of its turn has no focus to give back: a person who has gone elsewhere
  # while the request was out -- a click on the blank page -- stays there.
  test "after Move up on a top-level card, a focus put elsewhere before the answer lands stays there" do
    first = @page.content_blocks.create!(block_type: "image", position: 1)
    second = @page.content_blocks.create!(block_type: "image", position: 2)
    open_editor
    script_writes("hold")

    pick_by_keyboard(card(second), "Move up")
    await_js "window.__release.length === 1"
    assert focus_is_on("#{card(second)} .admin-block-card__handle"), "the moved card's handle has the focus at once"
    page.execute_script("document.activeElement.blur()")
    assert page.evaluate_script("document.activeElement === document.body")

    page.execute_script("window.__release[0]()")
    assert_selector "#content-blocks-status", text: "SAVED"
    assert_writes_settled
    await_frames # the move's turn has ended: what it would do to the focus is done
    assert page.evaluate_script("document.activeElement === document.body"), "the focus was pulled back to the card"
    assert_equal [ @section.id, second.id, first.id ], @page.content_blocks.top_level.reorder(:position).ids
  end

  # ---- The translation view (sections spec §4.5) ----------------------------

  test "on a translation tab a section is a heading over its blocks in reading order, each with its pair of fields" do
    with_locales(%w[en de], default: "en") do
      @left.update!(caption: "Left original")
      @right.update!(caption: "Right original")
      visit "/cs-studio/pages/#{@page.id}?locale=de"
      await_admin_controllers

      assert_selector ".admin-section-group", count: 1
      assert_selector ".admin-section-group > h3", text: "SECTION", exact_text: true
      assert_no_selector ".admin-block-tile"
      cards = page.all(".admin-section-group > .admin-block-card").map { |card| card["data-block-id"].to_i }
      assert_equal [ @left.id, @right.id ], cards
      assert_selector "[data-block-id='#{@left.id}'] .admin-translation-pair", text: "Left original"

      fill_in id: "block-#{@right.id}-caption", with: "Rechts"
      page.execute_script("document.activeElement.blur()")
      assert_selector "#block-#{@right.id}-save-status", text: "SAVED"
      assert_writes_settled
      assert_equal "Rechts", Mobility.with_locale(:de) { @right.reload.caption }
      assert_equal "Right original", Mobility.with_locale(:en) { @right.caption }
    end
  end

  # Why the group stands in the list with the section's `data-block-id`: the
  # cards around it are still moved on a translation tab, and the order a move
  # sends is the list's children -- which must name the section or it is
  # refused. The group itself has nothing to move it by.
  test "on a translation tab a card is moved past a section's group, and the group has no handle and no menu" do
    with_locales(%w[en de], default: "en") do
      below = @page.content_blocks.create!(block_type: "image", position: 1)
      visit "/cs-studio/pages/#{@page.id}?locale=de"
      await_admin_controllers
      group = "#content-blocks-list > .admin-section-group[data-block-id='#{@section.id}']"

      assert_selector group
      assert_no_selector "#{group} .admin-block-card__handle", visible: :all
      assert_no_selector "#{group} button[aria-label='Block actions'], #{group} button[aria-label='Section actions']", visible: :all
      # No lane on this tab, so nowhere to move a card into.
      assert_selector "#{card(below)} button[data-move='into'][disabled]", visible: :all

      pick_by_keyboard(card(below), "Move up")

      assert_selector "#content-blocks-status", text: "SAVED"
      assert_writes_settled
      assert_equal [ below.id, @section.id ], cards_in_list
      assert_equal [ below.id, @section.id ], @page.content_blocks.top_level.reorder(:position).ids
      assert_equal @section.id, @left.reload.section_id
    end
  end

  # ---- Small screens (sections spec §4.6) -----------------------------------

  # The breakpoint is the section card's own width (a container query), so
  # only a browser can show it. Wide first: the test would pass on lanes that
  # always stacked.
  test "below the width where the lanes fit side by side they stack, each under its column's label" do
    open_editor
    boxes = <<~JS
      (() => {
        const [first, second] = ["1", "2"].map((n) => document.getElementById("section-#{@section.id}-lane-" + n).getBoundingClientRect())
        return { beside: second.left >= first.right && Math.abs(second.top - first.top) < 2, stacked: second.top >= first.bottom }
      })()
    JS
    label_shown = "(() => { const r = document.querySelector('#section-#{@section.id}-lanes .admin-section-lane:nth-child(2) .admin-section-lane__label').getBoundingClientRect(); return r.width > 1 && r.height > 1 })()"

    assert_eventually(message: "the lanes are not side by side at the full width") { page.evaluate_script(boxes)["beside"] }
    assert_not page.evaluate_script(label_shown), "a column's label is shown although the lanes are side by side"

    page.driver.resize(520, 900)

    assert_eventually(message: "the lanes did not stack at 520px") { page.evaluate_script(boxes)["stacked"] }
    assert page.evaluate_script(label_shown), "a stacked lane does not show its column's label"
    assert_selector ".admin-section-lane__label", text: "Column 2", visible: :all
  ensure
    page.driver.resize(1400, 1400)
  end

  # ---- Unavailable types (sections spec §6) ---------------------------------

  # Spec §6 says Delete is the tile's only action; the menu moves were kept
  # for it on purpose (the grip moves it, so the keyboard must: see
  # `Admin::EditorScreen::BlockTileComponent`). What it loses is Duplicate.
  test "a block of a type that is gone is an Unavailable tile that can be moved and deleted, and not copied" do
    @left.update_columns(block_type: "gone/thing")
    open_editor

    assert_selector tile(@left), text: "Unavailable type — gone/thing"
    find(menu_button(tile(@left))).click
    assert_equal [ "Move up", "Move down", "Move to column…", "Move out of section", "Delete block…" ],
      page.all("#{tile(@left)} [role=menu] button").map(&:text)

    within(tile(@left)) { press "Delete block…" }
    within("dialog[open]") { press "Delete block" }

    assert_no_selector tile(@left)
    assert_not ContentBlock.exists?(@left.id)
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 1 block", exact_text: true
  end

  def lose_the_sections_type
    @section.update_columns(block_type: "gone/section")
  end

  test "a section whose type is gone shows its blocks under the Unavailable type card, and each opens its form" do
    lose_the_sections_type
    open_editor

    assert_selector "#{section_card}.border-danger", text: "Unavailable type — gone/section"
    assert_selector section_card, text: "Its blocks are still here. Remove the section and keep them, move them out one by one, or delete it with them."
    assert_equal [ @left.id ], tiles_in(1)
    assert_equal [ @right.id ], tiles_in(2)
    assert_no_selector "#{section_card} .admin-block-card__handle", visible: :all
    assert_no_selector "#{section_card} button[aria-label='Section actions']", visible: :all
    assert_no_selector "#{section_card} [id^='block-picker-']", visible: :all

    find(face(@left)).click
    assert_selector panel(@left), text: "Image · column 1"
    fill_in id: caption(@left), with: "Still editable"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "SAVED"
    assert_writes_settled
    assert_equal "Still editable", @left.reload.caption
  end

  # Its lanes take nothing (`admin--blocks#closed`): the server has no column
  # of it to put a block in. Asked of the controller as SortableJS asks it.
  test "a lane of a section whose type is gone takes no block, sorts nothing and sends no order" do
    lose_the_sections_type
    outside = @page.content_blocks.create!(block_type: "image", position: 1)
    open_editor
    count_writes

    answers = page.evaluate_script(<<~JS)
      (() => {
        const controller = #{blocks_controller}
        const lane = document.querySelector(#{lane(1).to_json})
        const card = document.querySelector(#{card(outside).to_json})
        const tile = document.querySelector(#{tile(@right).to_json})
        const own = document.querySelector(#{tile(@left).to_json})
        controller.move(own, lane, controller.snapshot())
        return { card: controller.accepts(lane, card), tile: controller.accepts(lane, tile), sorts: controller.laneSortables.get(lane).option("sort") }
      })()
    JS

    assert_equal({ "card" => false, "tile" => false, "sorts" => false }, answers)
    await_frames # a request the move had queued would have been sent by now
    assert_writes_settled
    assert_empty page.evaluate_script("window.__writes")
  end

  test "in a section whose type is gone a tile's only move is out, and no card is offered a way in" do
    below = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 1)
    lose_the_sections_type
    outside = @page.content_blocks.create!(block_type: "image", position: 1)
    open_editor

    %w[up down column].each do |move|
      assert_selector "#{tile(@left)} button[data-move='#{move}'][disabled]", visible: :all
      assert_selector "#{tile(below)} button[data-move='#{move}'][disabled]", visible: :all
    end
    assert_selector "#{tile(@left)} button[data-move='out']:not([disabled])", visible: :all
    assert_selector "#{card(outside)} button[data-move='into'][disabled]", visible: :all

    pick_by_keyboard(tile(@left), "Move out of section")

    assert_selector card(@left)
    assert_writes_settled
    assert_no_selector "#content-blocks-alert p"
    assert_equal [ @section.id, @left.id, outside.id ], @page.content_blocks.top_level.reorder(:position).ids
    assert_nil @left.reload.section_id
    assert_equal [ below.id ], tiles_in(1)
    assert_no_selector panel(@left), visible: :all
  end

  # With a real section beside it: the Move dialog offers that one's columns
  # only, and numbers it as the first section -- the unavailable card does
  # not read "Section" and is not counted.
  test "the Move dialog offers no column of a section whose type is gone and does not count it" do
    lose_the_sections_type
    real = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "two" })
    outside = @page.content_blocks.create!(block_type: "image", position: 2)
    open_editor

    pick_by_keyboard(card(outside), "Move into section…")

    assert_selector "dialog[open] #move-block-destination"
    assert_equal [ "Section 1 · column 1", "Section 1 · column 2" ], page.all("#move-block-destination option").map(&:text)
    assert_equal [ "section-#{real.id}-lane-1", "section-#{real.id}-lane-2" ], page.all("#move-block-destination option").map(&:value)
    within("dialog[open]") { press "Cancel" }
    assert_no_selector "dialog[open]"
  end

  test "Delete section and its blocks… on a section whose type is gone says how many blocks go with it, and deletes them" do
    lose_the_sections_type
    open_editor

    within("#{section_card} > div:first-child") { press "Delete section and its blocks…" }

    assert_selector "dialog[open]", text: "This also deletes the 2 blocks in it."
    within("dialog[open]") { press "Delete section" }

    assert_no_selector section_card
    assert_no_selector ".admin-block-tile"
    assert_empty @page.content_blocks.reload
  end

  # The safe way out of a section nobody can read: the wrapper goes, what was
  # in it stays, as cards where it stood and in the order it was read in.
  test "Remove section, keep blocks on a section whose type is gone puts its blocks in its place as cards in reading order" do
    above = @page.content_blocks.create!(block_type: "image", position: 0)
    @section.update_columns(position: 1)
    below_left = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    after = @page.content_blocks.create!(block_type: "image", position: 2)
    lose_the_sections_type
    open_editor

    within("#{section_card} > div:first-child") { press "Remove section, keep blocks" }

    assert_no_selector ".admin-section-card"
    assert_no_text "Unavailable type"
    assert_order_eventually([ above.id, @left.id, below_left.id, @right.id, after.id ]) { cards_in_list }
    assert_selector "#content-blocks-list > .admin-block-card", count: 5
    assert_no_selector ".admin-block-tile"
    assert_writes_settled
    assert_not ContentBlock.exists?(@section.id)
    assert_equal [ above.id, @left.id, below_left.id, @right.id, after.id ], @page.content_blocks.top_level.reorder(:position, :id).ids
    assert_equal [ nil ], @page.content_blocks.reload.map(&:section_id).uniq

    # A lifted block is a card like any other: it saves on its own base.
    fill_in id: caption(@left), with: "Kept, and edited as a card"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "SAVED"
    assert_writes_settled
    assert_equal "Kept, and edited as a card", @left.reload.caption
    assert_no_text "CHANGED ELSEWHERE"
  end

  # The same rule as in a section's menu: the removal's answer replaces the
  # blocks' forms, so it does not run over text that was refused.
  test "Remove section, keep blocks on a section whose type is gone does not run while a form holds text that was refused" do
    lose_the_sections_type
    open_editor
    find(face(@left)).click
    travel 1.minute do
      as(users(:two), channel: :admin) { ContentBlocks::Save.call(@left, translations: { "en" => { caption: "Theirs" } }) }
    end
    fill_in id: caption(@left), with: "Mine, refused"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE", wait: 8

    within("#{section_card} > div:first-child") { press "Remove section, keep blocks" }

    assert_selector "#toasts #toast-queue-hold[role=alert]", text: "Your last change wasn't saved, so this didn't run."
    assert_selector "#{section_card}.border-danger"
    assert_field caption(@left), with: "Mine, refused"
    assert_equal @section.id, @left.reload.section_id
    assert_selector "#{section_card} > div:first-child button:not([disabled])", text: "Remove section, keep blocks"
  end
end
