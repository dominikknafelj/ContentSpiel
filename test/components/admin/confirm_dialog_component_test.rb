require "test_helper"

class Admin::ConfirmDialogComponentTest < ViewComponent::TestCase
  test "renders a dialog with the given id, title and body" do
    render_inline Admin::ConfirmDialogComponent.new(id: "delete-page", title: "Delete this page?", body: "This can't be undone.")

    assert_selector "dialog#delete-page"
    assert_selector "dialog#delete-page", text: "Delete this page?"
    assert_text "This can't be undone."
  end

  test "cancel closes the native dialog with no JS (method=dialog)" do
    render_inline Admin::ConfirmDialogComponent.new(id: "delete-page", title: "Delete this page?")

    assert_selector "form[method='dialog'] button", text: "Cancel"
  end

  test "renders the caller-provided confirm action slot" do
    render_inline(Admin::ConfirmDialogComponent.new(id: "delete-page", title: "Delete this page?")) do |component|
      component.with_confirm_action { "<button type=\"submit\">Delete</button>".html_safe }
    end

    assert_selector "button", text: "Delete"
  end
end
