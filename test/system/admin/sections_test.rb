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
end
