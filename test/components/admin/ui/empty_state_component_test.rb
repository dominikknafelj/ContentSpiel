require "test_helper"

# The brand book's empty-state rule: "Empty states are one dim line plus an
# action, left-aligned where the first row would be. Don't centre them and
# don't add a second line in another style."
class Admin::Ui::EmptyStateComponentTest < ViewComponent::TestCase
  test "the title and the description are one dim paragraph, the title first, in one style" do
    render_inline Admin::Ui::EmptyStateComponent.new(title: "No blocks yet.", description: "Add your first block to get started.")

    assert_selector ".admin-empty-state > p", count: 1
    assert_selector ".admin-empty-state > p.text-sm.text-dim", text: "No blocks yet. Add your first block to get started.", exact_text: true
    assert_selector "p [data-empty-state-title]", text: "No blocks yet.", exact_text: true
    # One style: nothing inside the line is bolder, larger or another colour.
    assert_no_selector ".admin-empty-state [class*='font-'], .admin-empty-state [class*='text-ink'], .admin-empty-state [class*='text-meta']"
  end

  test "it is no heading and is not centred: left-aligned where the first row would be" do
    render_inline(Admin::Ui::EmptyStateComponent.new(title: "No posts yet.")) do |component|
      component.with_action { "<button type=\"button\">New post</button>".html_safe }
    end

    assert_no_selector "h1, h2, h3, h4, h5, h6"
    assert_no_selector ".text-center, .justify-center, .items-center, .mx-auto"
    assert_selector ".admin-empty-state.px-4.py-2\\.5"
  end

  test "draws no border of its own: it sits inside its list's card" do
    render_inline Admin::Ui::EmptyStateComponent.new(title: "No tags yet.")

    assert_no_selector ".border, .border-dashed"
  end

  test "description is optional: the title alone is the line" do
    render_inline Admin::Ui::EmptyStateComponent.new(title: "No tags yet.")

    assert_selector ".admin-empty-state > p", text: "No tags yet.", exact_text: true
  end

  test "renders an action slot after the line, left-aligned" do
    render_inline(Admin::Ui::EmptyStateComponent.new(title: "No posts yet.")) do |component|
      component.with_action { "<button type=\"button\">New post</button>".html_safe }
    end

    assert_selector ".admin-empty-state > p + div.justify-start button", text: "New post"
  end
end
