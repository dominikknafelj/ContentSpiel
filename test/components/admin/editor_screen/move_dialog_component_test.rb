require "test_helper"

class Admin::EditorScreen::MoveDialogComponentTest < ViewComponent::TestCase
  test "it is the Move block dialog with an empty, labelled select for admin--editor--blocks to fill" do
    render_inline Admin::EditorScreen::MoveDialogComponent.new

    assert_selector "dialog#move-block-dialog.admin-dialog h2", text: "Move block", visible: :all
    assert_selector "dialog label[for='move-block-destination']", text: "Move to", visible: :all
    assert_selector "dialog .admin-dialog__body select#move-block-destination.cs-select[data-admin--editor--blocks-target='destination']", visible: :all
    assert_no_selector "select option", visible: :all
  end

  # Cancel closes it without a script and without leaving the page; Move is
  # `admin--editor--blocks`' to act on. No form here sends anything.
  test "its footer is Cancel, a dialog form, and Move, an action of admin--editor--blocks" do
    render_inline Admin::EditorScreen::MoveDialogComponent.new

    assert_selector "dialog footer form[method='dialog'] button[type=submit]", text: "Cancel", visible: :all
    assert_selector "dialog footer > button[type=button][data-action='admin--editor--blocks#moveTo']", text: "Move", visible: :all
    assert_no_selector "dialog form:not([method='dialog'])", visible: :all
  end

  test "a trigger fills the dialog before it opens it" do
    assert_equal({ move: "into", action: "click->admin--editor--blocks#askWhere admin--ui--dialog#open", "admin--ui--dialog-id-param": "move-block-dialog" },
      Admin::EditorScreen::MoveDialogComponent.trigger("into"))
  end
end
