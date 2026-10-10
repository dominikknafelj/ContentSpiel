require "test_helper"

class Admin::Ui::EmptyStateComponentTest < ViewComponent::TestCase
  test "renders a title and optional description" do
    render_inline Admin::Ui::EmptyStateComponent.new(title: "No blocks yet", description: "Add your first block to get started.")

    assert_selector "h3", text: "No blocks yet"
    assert_text "Add your first block to get started."
  end

  test "draws no border of its own: it sits inside its list's card" do
    render_inline Admin::Ui::EmptyStateComponent.new(title: "No tags yet")

    assert_no_selector ".border, .border-dashed"
  end

  test "description is optional" do
    render_inline Admin::Ui::EmptyStateComponent.new(title: "No tags yet")

    assert_selector "h3", text: "No tags yet"
  end

  test "renders an action slot, e.g. a button" do
    render_inline(Admin::Ui::EmptyStateComponent.new(title: "No posts yet")) do |component|
      component.with_action { "<button type=\"button\">New post</button>".html_safe }
    end

    assert_selector "button", text: "New post"
  end
end
