require "application_system_test_case"

class Admin::SectionsSettingsSystemTest < Admin::SectionsSystemTestCase
  # ---- The section's own controls (sections spec §4.1) ----

  test "choosing a narrower layout folds the second lane into the first without losing the open form" do
    open_editor
    find(face(@right)).click
    fill_in id: caption(@right), with: "Typed before the fold"

    find("##{ActionView::RecordIdentifier.dom_id(@section)} button[aria-label='Layout']").click
    find("button[data-admin--editor--section-layout-param='one']").click

    assert_selector "#section-#{@section.id}-lanes [data-admin--editor--blocks-target='lane']", count: 1
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
    find("button[data-admin--editor--section-layout-param='one']").click
    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", count: 2

    assert_selector "#{face(@right)}[aria-expanded='true']"
    assert_selector "#{face(@left)}[aria-expanded='false']"
    fill_in id: caption(@right), with: "Typed after the fold"
    page.execute_script("document.activeElement.blur()")

    assert_selector "#block-#{@right.id}-save-status", text: "SAVED"
    assert_no_text "CHANGED ELSEWHERE"
    assert_equal "Typed after the fold", @right.reload.caption
    find(layout_button).click
    assert_selector "#{section_card} button[data-admin--editor--section-layout-param='one'][aria-current='true']"
    assert_selector "#{section_card} button[data-admin--editor--section-layout-param][aria-current='true']", count: 1
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
    assert_selector "#{section_card} [role=menu] [role=menuitem][data-admin--editor--section-layout-param]", count: 6
    # Opening focuses the first choice; two steps down is "Three columns".
    page.driver.browser.keyboard.type(:down, :down, :enter)

    assert_selector "#section-#{@section.id}-lanes [data-admin--editor--blocks-target='lane']", count: 3
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
    find("button[data-admin--editor--section-layout-param='two']").click

    assert_no_selector "#{section_card} [role=menu]"
    await_frames
    assert_writes_settled
    assert_equal [], page.evaluate_script("window.__writes")
    assert_equal true, focus_is_on(layout_button)
  end

  test "a layout chosen in a tab that is behind is refused as changed elsewhere, and nothing is folded" do
    open_editor
    backdate(@section, by: 1.minute)
    as_unheard(users(:two)) { assert ContentBlocks::Save.call(ContentBlock.find(@section.id), attributes: { settings: { "background" => "tinted" } }).ok? }

    find(layout_button).click
    find("button[data-admin--editor--section-layout-param='one']").click

    assert_selector "#block-#{@section.id}-save-status", text: "CHANGED ELSEWHERE"
    assert_selector "#section-#{@section.id}-lanes [data-admin--editor--blocks-target='lane']", count: 2
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
    assert_selector "#{section_card} [role=menu] [role=menuitem][data-admin--editor--section-layout-param]", count: 6

    assert_selector "#block-#{@section.id}-save-status", text: "SAVED"
    assert_writes_settled
    await_frames
    assert_equal "tinted", @section.reload.settings["background"]
    assert_selector "#{section_card} [role=menu] [role=menuitem][data-admin--editor--section-layout-param]", count: 6
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
        if (String(url.url || url).includes("/cs-studio/editing/")) return originalFetch(url, options) // a claim is not the layout's save
        window.__writes += 1
        if (window.__writes > 1) return originalFetch(url, options)
        return Promise.resolve(new Response("", { status: 422, headers: { "Content-Type": "text/vnd.turbo-stream.html" } }))
      }
    JS

    find(layout_button).click
    find("button[data-admin--editor--section-layout-param='one']").click
    # Not `assert_writes_settled`: a form whose save failed is not settled.
    assert_eventually(message: "the layout was never sent") { page.evaluate_script("window.__writes") == 1 }
    assert_no_selector "#{section_card} [role=menu]"
    assert_equal "two", @section.reload.settings["layout"]

    # The pick alone, with the menu closed: opening the menu moves the focus
    # inside the form, and a form whose save failed sends again on that by
    # itself -- which is not the rule this is about.
    page.execute_script("document.querySelector(#{"#{section_card} button[data-admin--editor--section-layout-param='one']".to_json}).click()")

    assert_selector "#section-#{@section.id}-lanes [data-admin--editor--blocks-target='lane']", count: 1
    assert_writes_settled
    assert_equal 2, page.evaluate_script("window.__writes")
    assert_equal "one", @section.reload.settings["layout"]
  end
end
