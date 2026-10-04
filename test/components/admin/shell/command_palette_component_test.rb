require "test_helper"

class Admin::Shell::CommandPaletteComponentTest < ViewComponent::TestCase
  test "a labelled modal dialog with a combobox search field and an empty results frame" do
    render_inline(Admin::Shell::CommandPaletteComponent.new)
    assert_selector "dialog#command-palette.admin-dialog.admin-palette[aria-label='Jump to…'][data-dialog-width=form]"
    assert_selector "dialog input[role=combobox][aria-controls=jump-results][aria-label='Jump to…'][autocomplete=off]"
    assert_selector "dialog input[data-action*='admin--command-palette#search'][data-action*='admin--command-palette#move']"
    assert_selector "dialog turbo-frame#jump-results[data-action*='admin--command-palette#loaded']:not([src])"
  end
end
