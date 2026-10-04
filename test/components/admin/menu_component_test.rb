require "test_helper"

class Admin::MenuComponentTest < ViewComponent::TestCase
  test "a button that owns a hidden menu panel" do
    render_inline(Admin::MenuComponent.new(label: "More")) do |menu|
      menu.with_item { "<a href='/a'>Rename</a>".html_safe }
      menu.with_item { "<a href='/b'>Delete…</a>".html_safe }
    end
    assert_selector "[data-controller='admin--menu'] button[aria-haspopup=menu][aria-expanded=false]", text: "More"
    assert_selector "[role=menu][hidden] a", count: 2, visible: :all
  end

  test "left alignment hangs the panel from the left edge" do
    render_inline(Admin::MenuComponent.new(label: "More", align: :left)) { |menu| menu.with_item { "x" } }
    assert_selector "[role=menu].left-0", visible: :all
    assert_no_selector "[role=menu].right-0", visible: :all
  end

  test "aria_label names an icon-only trigger; close_on_select closes the panel on a pick" do
    render_inline(Admin::MenuComponent.new(label: "⋯", aria_label: "More actions", close_on_select: true)) { |menu| menu.with_item { "x" } }
    assert_selector "button[aria-label='More actions']", text: "⋯"
    assert_selector "[role=menu][data-action~='click->admin--menu#select']", visible: :all
  end

  test "without close_on_select the panel stays open on a pick" do
    render_inline(Admin::MenuComponent.new(label: "More")) { |menu| menu.with_item { "x" } }
    assert_no_selector "[role=menu][data-action]", visible: :all
  end
end
