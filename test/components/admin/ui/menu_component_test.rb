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

  # A panel that lists things rather than offering actions (everyone behind
  # presence's group): it is no ARIA menu; pressing the button moves the focus
  # into the list, which is named.
  test "a list panel: list roles and a name, it takes the focus itself, and it closes when the pointer and the focus have left" do
    render_inline(Admin::Ui::MenuComponent.new(label: "+2", list: true, list_label: "Everyone with this open")) do |menu|
      menu.with_item { "Ann" }
      menu.with_item { "Bob" }
    end

    assert_selector "[data-controller='admin--ui--menu'] button[aria-expanded=false][data-action='admin--ui--menu#enter']", text: "+2"
    # What opens is a list, not a menu of actions: the button does not say
    # "menu" (`aria-haspopup="true"` means that), only that it is collapsed.
    assert_no_selector "button[aria-haspopup]"
    assert_no_selector "button[aria-controls]"
    assert_selector "[role=list][hidden][tabindex='-1'][aria-label='Everyone with this open'] > [role=listitem]", count: 2, visible: :all
    assert_no_selector "[role=menu], [role=none]", visible: :all
    assert_equal %w[click@window->admin--ui--menu#closeOutside keydown->admin--ui--menu#keydown mouseleave->admin--ui--menu#leave focusout->admin--ui--menu#leave],
      page.find("[data-controller='admin--ui--menu']")["data-action"].split
  end

  test "a list panel with an id is what its button says it controls" do
    render_inline(Admin::Ui::MenuComponent.new(label: "+2", list: true, list_label: "Everyone", panel_id: "people-list")) { |menu| menu.with_item { "Ann" } }

    assert_selector "button[aria-controls=people-list][aria-expanded=false]:not([aria-haspopup])"
    assert_selector "[role=list]#people-list", visible: :all
  end

  test "an ordinary menu has none of the hover and focus actions" do
    render_inline(Admin::Ui::MenuComponent.new(label: "More")) { |menu| menu.with_item { "x" } }

    assert_equal "click@window->admin--ui--menu#closeOutside keydown->admin--ui--menu#keydown", page.find("[data-controller='admin--ui--menu']")["data-action"]
    assert_selector "button[data-action='admin--ui--menu#toggle']"
    assert_selector "[role=menu] > [role=none]", visible: :all
    assert_no_selector "[role=menu][tabindex], [role=menu][aria-label]", visible: :all
  end
end
