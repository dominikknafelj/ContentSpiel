require "test_helper"

class Admin::Shell::TopBarComponentTest < ViewComponent::TestCase
  test "the menu button controls the sidebar drawer" do
    render_inline(Admin::Shell::TopBarComponent.new)
    assert_selector ".admin-top-bar button[aria-label='Open navigation'][aria-controls=sidebar][aria-expanded=false][data-action='admin--drawer#toggle']"
    assert_selector "button[data-action='admin--command-palette#open']"
    assert_no_selector "button[aria-controls=tree-column]"
  end

  test "a screen with a tree column also gets the Pages button" do
    render_inline(Admin::Shell::TopBarComponent.new(tree: true))
    assert_selector "button[aria-controls=tree-column][aria-expanded=false]", text: "Pages"
  end
end
