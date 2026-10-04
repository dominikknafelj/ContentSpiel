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

  test "the sidebar button opens it too, and nonsense shows the no-results line" do
    sign_in_via_form users(:one)
    await_admin_controllers
    press "Jump to…"
    assert_selector "dialog#command-palette[open]"
    find("dialog#command-palette input").set("zzzqqq")
    assert_text "No results for “zzzqqq”."
  end
end
