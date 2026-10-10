require "test_helper"

class Admin::Ui::DialogComponentTest < ViewComponent::TestCase
  test "a titled dialog with a close button, labelled by its title" do
    render_inline(Admin::Ui::DialogComponent.new(id: "d1", title: "New post", width: :form)) { "Body" }
    assert_selector "dialog#d1.admin-dialog[aria-labelledby='d1-title'][data-dialog-width=form]"
    assert_selector "#d1-title", text: "New post"
    assert_selector "dialog#d1 form[method=dialog] button[aria-label='Close']"
    assert_text "Body"
  end

  test "open_on_load marks the dialog for the server-requested open, and is absent otherwise" do
    render_inline(Admin::Ui::DialogComponent.new(id: "d4", title: "t", open_on_load: true)) { "Body" }
    assert_selector "dialog#d4[data-admin--dialog-open-on-load]", visible: :all

    render_inline(Admin::Ui::DialogComponent.new(id: "d5", title: "t")) { "Body" }
    assert_no_selector "dialog#d5[data-admin--dialog-open-on-load]", visible: :all
  end

  # Round 3 Task 9: a dialog whose height changes while open hangs from a fixed
  # top edge, like the media picker; the rule and the opt-in are both pinned.
  test "hang marks the dialog for the fixed top edge, and is absent otherwise" do
    render_inline(Admin::Ui::DialogComponent.new(id: "d6", title: "t", hang: true)) { "Body" }
    assert_selector "dialog#d6[data-dialog-hang]", visible: :all

    render_inline(Admin::Ui::DialogComponent.new(id: "d7", title: "t")) { "Body" }
    assert_no_selector "dialog#d7[data-dialog-hang]", visible: :all

    assert_match(/\.admin-dialog\[data-dialog-hang\] \{ margin-top: 7\.5vh; \}/, Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read)
  end

  test "an unknown width is a programming error" do
    assert_raises(ArgumentError) { Admin::Ui::DialogComponent.new(id: "d", title: "t", width: :huge) }
  end

  test "the footer slot renders only when given" do
    render_inline(Admin::Ui::DialogComponent.new(id: "d2", title: "t")) { "Body" }
    assert_no_selector "dialog#d2 footer"

    render_inline(Admin::Ui::DialogComponent.new(id: "d3", title: "t")) { |d| d.with_footer { "Actions" } }
    assert_selector "dialog#d3 footer", text: "Actions"
  end
end
