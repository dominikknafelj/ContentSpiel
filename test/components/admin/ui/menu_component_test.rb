require "test_helper"

class Admin::Ui::MenuComponentTest < ViewComponent::TestCase
  test "a button that owns a hidden menu panel" do
    render_inline(Admin::Ui::MenuComponent.new(label: "More")) do |menu|
      menu.with_item { "<a href='/a'>Rename</a>".html_safe }
      menu.with_item { "<a href='/b'>Delete…</a>".html_safe }
    end
    assert_selector "[data-controller='admin--ui--menu'] button[aria-haspopup=menu][aria-expanded=false]", text: "More"
    assert_selector "[role=menu][hidden] a", count: 2, visible: :all
  end

  test "left alignment hangs the panel from the left edge" do
    render_inline(Admin::Ui::MenuComponent.new(label: "More", align: :left)) { |menu| menu.with_item { "x" } }
    assert_selector "[role=menu].left-0", visible: :all
    assert_no_selector "[role=menu].right-0", visible: :all
  end

  test "aria_label names an icon-only trigger; close_on_select closes the panel on a pick" do
    render_inline(Admin::Ui::MenuComponent.new(label: "⋯", aria_label: "More actions", close_on_select: true)) { |menu| menu.with_item { "x" } }
    assert_selector "button[aria-label='More actions']", text: "⋯"
    assert_selector "[role=menu][data-action~='click->admin--ui--menu#select']", visible: :all
  end

  test "without close_on_select the panel stays open on a pick" do
    render_inline(Admin::Ui::MenuComponent.new(label: "More")) { |menu| menu.with_item { "x" } }
    assert_no_selector "[role=menu][data-action]", visible: :all
  end

  # A panel that lists things rather than offering actions (presence's "+N"):
  # it is no ARIA menu, and it opens on hover and focus as well as a click.
  test "a list panel: list roles, and it opens on hover, focus and click and closes when both have left" do
    render_inline(Admin::Ui::MenuComponent.new(label: "+2", list: true)) do |menu|
      menu.with_item { "Ann" }
      menu.with_item { "Bob" }
    end

    assert_selector "[data-controller='admin--ui--menu'] button[aria-haspopup=true][aria-expanded=false][data-action='admin--ui--menu#show']", text: "+2"
    assert_selector "[role=list][hidden] > [role=listitem]", count: 2, visible: :all
    assert_no_selector "[role=menu], [role=none]", visible: :all
    actions = page.find("[data-controller='admin--ui--menu']")["data-action"].split
    %w[click@window->admin--ui--menu#closeOutside keydown->admin--ui--menu#keydown mouseenter->admin--ui--menu#show
       mouseleave->admin--ui--menu#leave focusin->admin--ui--menu#show focusout->admin--ui--menu#leave].each { |action| assert_includes actions, action }
  end

  test "an ordinary menu has none of the hover and focus actions" do
    render_inline(Admin::Ui::MenuComponent.new(label: "More")) { |menu| menu.with_item { "x" } }

    assert_equal "click@window->admin--ui--menu#closeOutside keydown->admin--ui--menu#keydown", page.find("[data-controller='admin--ui--menu']")["data-action"]
    assert_selector "button[data-action='admin--ui--menu#toggle']"
    assert_selector "[role=menu] > [role=none]", visible: :all
  end
end
