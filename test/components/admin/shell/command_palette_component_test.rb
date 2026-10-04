require "test_helper"

class Admin::Shell::CommandPaletteComponentTest < ViewComponent::TestCase
  test "a labelled modal dialog with a combobox search field and an empty results frame" do
    render_inline(Admin::Shell::CommandPaletteComponent.new)
    assert_selector "dialog#command-palette.admin-dialog.admin-palette[aria-label='Jump to…'][data-dialog-width=form]"
    assert_selector "dialog input[role=combobox][aria-controls=jump-listbox][aria-label='Jump to…'][autocomplete=off]"
    assert_selector "dialog input[data-action*='admin--command-palette#search'][data-action*='admin--command-palette#move']"
    # What `aria-controls` names exists, as a listbox, before any answer has loaded.
    assert_selector "dialog turbo-frame#jump-results > #jump-listbox[role=listbox]", visible: :all
    assert_selector "dialog turbo-frame#jump-results[data-action*='admin--command-palette#loaded']:not([src])"
  end

  test "an ESC chip beside the input and a key-hint footer" do
    render_inline(Admin::Shell::CommandPaletteComponent.new)
    assert_selector "dialog kbd", text: "ESC", visible: :all
    assert_selector "dialog .admin-palette__hints", text: "↑↓ MOVE · ↵ OPEN · ⌘↵ NEW TAB", visible: :all
  end
end
