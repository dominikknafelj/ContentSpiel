require "application_system_test_case"

class CommandPaletteTest < ApplicationSystemTestCase
  test "Ctrl+K opens, filters, and Enter goes to the first result" do
    post = create_post(title: "Palette destination")
    sign_in_via_form users(:one)
    await_admin_controllers
    find("body").send_keys([ :control, "k" ])
    assert_selector "dialog#command-palette[open]"
    find("dialog#command-palette input").set("Palette dest")
    assert_selector "#jump-results [role=option][aria-selected=true]", text: post.title
    find("dialog#command-palette input").send_keys(:enter)
    assert_selector "h1", text: post.title
    assert_no_selector "dialog#command-palette[open]"
  end

  # The input keeps focus throughout, so the selected row reaches a screen
  # reader only through `aria-activedescendant` -- which must always name
  # the option that is selected, inside the listbox `aria-controls` names.
  test "the arrow keys move aria-activedescendant along with the selection" do
    create_post(title: "Palette first")
    create_post(title: "Palette second")
    sign_in_via_form users(:one)
    await_admin_controllers
    find("body").send_keys([ :control, "k" ])
    input = find("dialog#command-palette input")
    assert_selector "##{input["aria-controls"]}[role=listbox]", visible: :all

    input.set("Palette")
    assert_selector "#jump-results [role=option]", minimum: 2
    assert_selector "#jump-results [role=option][aria-selected=true]", count: 1
    first = find("#jump-results [role=option][aria-selected=true]")[:id]
    assert first.present?
    assert_equal first, input["aria-activedescendant"]
    assert_selector "##{input["aria-controls"]}[role=listbox] [role=group][aria-labelledby] ##{first}"

    input.send_keys(:down)
    second = find("#jump-results [role=option][aria-selected=true]")[:id]
    assert_not_equal first, second
    assert_equal second, input["aria-activedescendant"]

    input.set("zzzqqq")
    assert_text "No results for “zzzqqq”."
    assert_nil input["aria-activedescendant"]
  end

  test "the sidebar button opens it too, and nonsense shows the no-results line" do
    sign_in_via_form users(:one)
    await_admin_controllers
    press "Jump to…"
    assert_selector "dialog#command-palette[open]"
    find("dialog#command-palette input").set("zzzqqq")
    assert_text "No results for “zzzqqq”."
  end

  test "typing a new query and pressing Enter at once follows the new query's result, never the old one" do
    create_post(title: "Alpha stale target")
    beta = create_post(title: "Beta fresh target")
    sign_in_via_form users(:one)
    await_admin_controllers
    find("body").send_keys([ :control, "k" ])
    input = find("dialog#command-palette input")
    input.set("Alpha")
    assert_selector "#jump-results [role=option][aria-selected=true]", text: "Alpha stale target"
    input.set("Beta")
    input.send_keys(:enter)
    assert_selector "h1", text: beta.title
  end

  test "typing a new query and pressing Cmd/Ctrl+Enter at once opens the new query's result in a new tab, not this one" do
    create_post(title: "Alpha stale target")
    beta = create_post(title: "Beta fresh target")
    sign_in_via_form users(:one)
    await_admin_controllers
    page.execute_script("window.__opened = []; window.open = (...args) => { window.__opened.push(args); return null }")
    find("body").send_keys([ :control, "k" ])
    input = find("dialog#command-palette input")
    input.set("Alpha")
    assert_selector "#jump-results [role=option][aria-selected=true]", text: "Alpha stale target"
    input.set("Beta")
    input.send_keys([ :control, :enter ])
    assert_selector "#jump-results [role=option][aria-selected=true]", text: beta.title
    await_js "window.__opened.length > 0"
    opened = page.evaluate_script("window.__opened")
    assert_equal 1, opened.size
    assert_match(%r{/cs-studio/posts/#{beta.id}\b}, opened.first[0])
    assert_equal [ "_blank", "noopener" ], opened.first[1..]
    assert_current_path admin_root_path
  end

  # The moment between the matching answer being drawn and `loaded` running
  # (`turbo:frame-render`, then `turbo:frame-load`): the rows are right, none
  # is selected yet. Enter is pressed exactly there.
  test "Enter pressed after the answer is drawn but before it is selected still follows the first row" do
    create_post(title: "Alpha stale target")
    beta = create_post(title: "Beta fresh target")
    sign_in_via_form users(:one)
    await_admin_controllers
    find("body").send_keys([ :control, "k" ])
    input = find("dialog#command-palette input")
    input.set("Alpha")
    assert_selector "#jump-results [role=option][aria-selected=true]", text: "Alpha stale target"
    page.execute_script(<<~JS)
      const frame = document.querySelector("#command-palette turbo-frame")
      const press = () => {
        if (frame.querySelector("[data-query]")?.dataset.query !== "Beta") return
        frame.removeEventListener("turbo:frame-render", press)
        document.querySelector("#command-palette input").dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
      }
      frame.addEventListener("turbo:frame-render", press)
    JS
    input.set("Beta")
    assert_selector "h1", text: beta.title
  end

  test "an empty result offers New post" do
    sign_in_via_form users(:one)
    await_admin_controllers
    press "Jump to…"
    find("dialog#command-palette input").set("zzzqqq")
    assert_link "New post"
  end

  test "Cmd+Enter opens the selected row in a new tab and leaves the palette where it is" do
    post = create_post(title: "Newtab destination")
    sign_in_via_form users(:one)
    await_admin_controllers
    page.execute_script("window.__opened = []; window.open = (...args) => { window.__opened.push(args); return null }")
    find("body").send_keys([ :control, "k" ])
    input = find("dialog#command-palette input")
    input.set("Newtab dest")
    assert_selector "#jump-results [role=option][aria-selected=true]", text: post.title
    assert_selector "#jump-results [role=option][aria-selected=true] .admin-palette__enter", text: "↵"

    input.send_keys([ :control, :enter ])
    opened = page.evaluate_script("window.__opened")
    assert_equal 1, opened.size
    assert_match(%r{/cs-studio/posts/#{post.id}\b}, opened.first[0])
    assert_equal [ "_blank", "noopener" ], opened.first[1..]
    assert_selector "dialog#command-palette[open]"
    assert_current_path admin_root_path
  end

  test "the palette shows the hint row, the Esc chip and a Settings group that holds no sections" do
    sign_in_via_form users(:one)
    await_admin_controllers
    find("body").send_keys([ :control, "k" ])
    assert_selector "dialog#command-palette .admin-palette__hints", text: "NEW TAB"
    assert_selector "dialog#command-palette kbd", text: /esc/i
    assert_selector "#jump-results [role=group] [role=presentation]", text: /sections/i
    within(find("#jump-results [role=group][aria-labelledby]", text: "Settings › Languages")) do
      assert_no_text "Dashboard"
    end
  end

  # Review B, M5: the shortcut is heard on `window`, so also while another
  # modal dialog is up. The palette used to stack on top of it, and following
  # a row left that dialog's typed input behind without a word.
  test "Ctrl+K does nothing while another dialog is open" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form users(:one)
    visit "/cs-studio/pages/#{root_page.id}"
    await_admin_controllers

    find("#tree a", text: "+ New page").click
    assert_selector "dialog#new-page-dialog[open]"
    find("dialog#new-page-dialog").send_keys([ :control, "k" ])
    await_frames
    assert_no_selector "dialog#command-palette[open]"
    assert_selector "dialog#new-page-dialog[open]"

    find("dialog#new-page-dialog").send_keys(:escape)
    assert_no_selector "dialog[open]"
    find("body").send_keys([ :control, "k" ])
    assert_selector "dialog#command-palette[open]"
  end
end
