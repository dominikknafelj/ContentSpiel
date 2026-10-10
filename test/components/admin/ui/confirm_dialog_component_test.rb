require "test_helper"

class Admin::Ui::ConfirmDialogComponentTest < ViewComponent::TestCase
  test "renders a dialog with the given id, title and body" do
    render_inline Admin::Ui::ConfirmDialogComponent.new(id: "delete-page", title: "Delete this page?", body: "This can't be undone.")

    assert_selector "dialog#delete-page"
    assert_selector "dialog#delete-page", text: "Delete this page?"
    assert_text "This can't be undone."
  end

  test "cancel closes the native dialog with no JS (method=dialog)" do
    render_inline Admin::Ui::ConfirmDialogComponent.new(id: "delete-page", title: "Delete this page?")

    assert_selector "form[method='dialog'] button", text: "Cancel"
  end

  test "renders the caller-provided confirm action slot" do
    render_inline(Admin::Ui::ConfirmDialogComponent.new(id: "delete-page", title: "Delete this page?")) do |component|
      component.with_confirm_action { "<button type=\"submit\">Delete</button>".html_safe }
    end

    assert_selector "button", text: "Delete"
  end

  test "a destructive confirm starts focus on Cancel" do
    render_inline(Admin::Ui::ConfirmDialogComponent.new(id: "c1", title: "Delete this tag?", destructive: true)) do |dialog|
      dialog.with_confirm_action { "<button>Delete tag</button>".html_safe }
    end
    assert_selector "dialog#c1[data-dialog-width=confirm][data-destructive]"
    assert_selector "dialog#c1 button[autofocus]", text: "Cancel"
  end

  test "a non-destructive confirm leaves focus to the first field or button" do
    render_inline(Admin::Ui::ConfirmDialogComponent.new(id: "c2", title: "Turn off Deutsch?")) { |d| d.with_confirm_action { "x" } }
    assert_no_selector "dialog#c2 button[autofocus]"
  end

  # The box is plain: nothing in the shared dialog hides it. A dialog that
  # wants an empty box out of the way says so on what it puts there (the
  # block's delete dialog and its notes warning, `data-notes-alone`).
  test "the details box carries no rule of its own about what it holds" do
    render_inline(Admin::Ui::ConfirmDialogComponent.new(id: "c2", title: "Delete this group?")) do |dialog|
      dialog.with_details { "Two tokens are revoked.".html_safe }
    end

    assert_selector "dialog#c2 div[class='mt-2 text-ink']", text: "Two tokens are revoked."
  end
end
