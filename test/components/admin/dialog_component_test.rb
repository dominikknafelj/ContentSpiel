require "test_helper"

class Admin::DialogComponentTest < ViewComponent::TestCase
  test "a titled dialog with a close button, labelled by its title" do
    render_inline(Admin::DialogComponent.new(id: "d1", title: "New post", width: :form)) { "Body" }
    assert_selector "dialog#d1.admin-dialog[aria-labelledby='d1-title'][data-dialog-width=form]"
    assert_selector "#d1-title", text: "New post"
    assert_selector "dialog#d1 form[method=dialog] button[aria-label='Close']"
    assert_text "Body"
  end

  test "an unknown width is a programming error" do
    assert_raises(ArgumentError) { Admin::DialogComponent.new(id: "d", title: "t", width: :huge) }
  end

  test "the footer slot renders only when given" do
    render_inline(Admin::DialogComponent.new(id: "d2", title: "t")) { "Body" }
    assert_no_selector "dialog#d2 footer"

    render_inline(Admin::DialogComponent.new(id: "d3", title: "t")) { |d| d.with_footer { "Actions" } }
    assert_selector "dialog#d3 footer", text: "Actions"
  end
end
