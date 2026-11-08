require "test_helper"

class Admin::Shell::TopBarComponentTest < ViewComponent::TestCase
  test "the menu button controls the sidebar drawer" do
    render_inline(Admin::Shell::TopBarComponent.new)
    assert_selector ".admin-top-bar button[aria-label='Open navigation'][aria-controls=sidebar][aria-expanded=false][data-action='admin--shell--drawer#toggle']"
    assert_selector "button[data-action='admin--shell--command-palette#open']"
    assert_no_selector "button[aria-controls=tree-column]"
  end

  test "a screen with the Pages tree gets its button, named and worded by its subject" do
    render_inline(Admin::Shell::TopBarComponent.new(tree: "pages"))
    assert_selector "button.admin-top-bar__tree[aria-controls=tree-column][aria-expanded=false][aria-label='Open page tree']", text: "Pages ▾"
  end

  test "the fold buttons, the divider and the top bar's tree button say what the column holds" do
    render_inline(Admin::Shell::TopBarComponent.new(tree: "mind_graph"))
    assert_selector "button.admin-top-bar__tree[aria-controls=tree-column][aria-label='Open list']", text: "List ▾"

    assert_raises(KeyError) { Admin::Shell::TopBarComponent.new(tree: "posts") }
  end

  test "the top bar's words are keys" do
    render_inline(Admin::Shell::TopBarComponent.new(tree: "pages"))
    words = ->(key) { I18n.t("admin.components.shell.top_bar.#{key}") }

    assert_selector "button[aria-controls=sidebar][aria-label='#{words.(:navigation)}']"
    assert_selector ".admin-wordmark", text: words.(:wordmark)
    assert_selector "button[data-action='admin--shell--command-palette#open'][aria-label='#{words.(:jump)}'] .text-label", text: words.(:shortcut)
    assert_equal [ "Open navigation", "CONTENT·SPIEL", "Jump to…", "⌘K" ], %i[navigation wordmark jump shortcut].map(&words)
  end
end
