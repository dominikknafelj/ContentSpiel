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

  test "an empty result offers New post" do
    sign_in_via_form users(:one)
    await_admin_controllers
    press "Jump to…"
    find("dialog#command-palette input").set("zzzqqq")
    assert_link "New post"
  end
end
