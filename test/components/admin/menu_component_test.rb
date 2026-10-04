require "test_helper"

class Admin::MenuComponentTest < ViewComponent::TestCase
  test "a button that owns a hidden menu panel" do
    render_inline(Admin::MenuComponent.new(label: "More")) do |menu|
      menu.with_item { "<a href='/a'>Rename</a>".html_safe }
      menu.with_divider
      menu.with_item { "<a href='/b'>Delete…</a>".html_safe }
    end
    assert_selector "[data-controller='admin--menu'] button[aria-haspopup=menu][aria-expanded=false]", text: "More"
    assert_selector "[role=menu][hidden] a", count: 2, visible: :all
    assert_selector "[role=menu] [role=separator]", visible: :all
  end

  test "left alignment hangs the panel from the left edge" do
    render_inline(Admin::MenuComponent.new(label: "More", align: :left)) { |menu| menu.with_item { "x" } }
    assert_selector "[role=menu].left-0", visible: :all
    assert_no_selector "[role=menu].right-0", visible: :all
  end
end
