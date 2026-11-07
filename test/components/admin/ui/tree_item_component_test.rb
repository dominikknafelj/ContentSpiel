require "test_helper"

# The shared tree row: its markup, its words and that its classes are the
# `.admin-tree` block's. How it looks is the block's (admin_design_rules_test.rb,
# admin_contrast_test.rb); folding it is the tree's script's.
class Admin::Ui::TreeItemComponentTest < ViewComponent::TestCase
  STYLESHEET = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css")

  def render_row(title: "About us", **options, &block)
    render_inline(Admin::Ui::TreeItemComponent.new(id: "tree-row-1", title: title, **options)) do |item|
      item.with_title { %(<a href="/a" data-tree-focus>#{ERB::Util.html_escape(title)}</a>).html_safe }
      block&.call(item)
    end
  end

  def stylesheet = STYLESHEET.read.gsub(%r{/\*.*?\*/}m, "")

  test "only the selected row is semibold, and the selection is the class the tree's script moves" do
    render_row(selected: true)
    assert_selector "div#tree-row-1.admin-tree-row.admin-tree-row--selected"

    render_row
    assert_selector "div#tree-row-1.admin-tree-row"
    assert_no_selector ".admin-tree-row--selected"
    assert_no_selector "[class*='font-']"

    assert_match(/\.admin-tree-row--selected \.admin-tree-row__title\s*\{\s*font-weight:\s*600;\s*\}/, stylesheet)
    assert_match(/\.admin-tree-row__title\s*\{[^}]*font-weight:\s*400;/, stylesheet)
    semibold = stylesheet.scan(/([^{}]*\.admin-tree[^{}]*)\{[^}]*font-weight:\s*(?:600|700|bold)/).flatten.map(&:squish)
    assert_equal [ ".admin-tree-row--selected .admin-tree-row__title" ], semibold, "one tree rule makes a title heavier: the selected row's"
  end

  test "a parent draws a disclosure button that names its branch and says whether it is open; a leaf keeps an empty column; a flat row has none" do
    render_row(parent: true, controls: "tree-children-1")
    assert_selector "button.admin-tree-row__disclosure[type=button][aria-expanded=true][aria-controls='tree-children-1'][aria-label='Fold About us']"
    assert_selector "button.admin-tree-row__disclosure svg[aria-hidden=true]"
    assert_selector "button.admin-tree-row__disclosure[data-action='admin--tree--disclosure#toggle']"

    render_row
    assert_no_selector "button"
    assert_selector "span.admin-tree-row__disclosure:empty", count: 1

    render_row(flat: true)
    assert_selector "div.admin-tree-row.admin-tree-row--flat"
    assert_no_selector ".admin-tree-row__disclosure"

    render_row(parent: true, flat: true)
    assert_no_selector ".admin-tree-row__disclosure"
  end

  test "a folded parent says so and controls its children's list" do
    render_row(parent: true, folded: true, controls: "tree-children-1")
    assert_selector "button.admin-tree-row__disclosure[aria-expanded=false][aria-controls='tree-children-1'][aria-label='Unfold About us']"
  end

  test "a context-only row is meta, with no link and no handle drawn by the screen" do
    render_inline(Admin::Ui::TreeItemComponent.new(id: "tree-row-1", title: "Members", parent: true, controls: "tree-children-1", context_only: true)) do |item|
      item.with_title { "Members" }
    end
    assert_selector "div.admin-tree-row.admin-tree-row--context-only .admin-tree-row__title", text: "Members", exact_text: true
    assert_no_selector "a"
    assert_no_selector ".admin-tree-node__handle"
    assert_selector "button.admin-tree-row__disclosure[aria-label='Fold Members']", count: 1
    assert_match(/\.admin-tree-row--context-only \.admin-tree-row__title\s*\{\s*color:\s*var\(--cs-meta\);\s*\}/, stylesheet)
  end

  test "the root draws the home glyph and other rows the page glyph, both hidden from a screen reader" do
    home = render_row(root: true).at_css(".admin-tree-row__mark svg")
    page_mark = render_row.at_css(".admin-tree-row__mark svg")

    [ home, page_mark ].each do |svg|
      assert_equal "true", svg["aria-hidden"]
      assert_equal %w[14 14 1.3], [ svg["width"], svg["height"], svg["stroke-width"] ]
    end
    assert_not_equal home.at_css("path")["d"], page_mark.at_css("path")["d"]

    render_row { |item| item.with_mark { %(<span data-own-mark></span>).html_safe } }
    assert_selector ".admin-tree-row__mark > [data-own-mark]"
    assert_no_selector ".admin-tree-row__mark svg"
  end

  test "the slots are drawn in their order: handle, disclosure, mark, title, state, trailing, add" do
    render_row(parent: true, controls: "tree-children-1") do |item|
      item.with_handle { %(<button type="button" class="admin-tree-node__handle" data-part="handle">⠿</button>).html_safe }
      item.with_state { %(<span data-part="state"></span>).html_safe }
      item.with_trailing { %(<span data-part="first"></span>).html_safe }
      item.with_trailing { %(<span data-part="second"></span>).html_safe }
      item.with_add(label: "Add a page under About us", href: "/new")
    end

    parts = page.find("div.admin-tree-row").native.element_children.map { |child| child["data-part"] || child["class"].split.first }
    assert_equal %w[handle admin-tree-row__disclosure admin-tree-row__mark admin-tree-row__title admin-tree-row__state admin-tree-row__trailing admin-tree-row__add], parts
    assert_selector ".admin-tree-row__state > [data-part=state]"
    assert_equal %w[first second], page.all(".admin-tree-row__trailing > span").map { |span| span["data-part"] }
    assert_selector ".admin-tree-row__title[title='About us'] > a[data-tree-focus]", text: "About us"
  end

  test "the row carries the hooks a find and the scripts read, and the screen's own" do
    render_row(title: "Über uns", path: "/de/ueber-uns", node_id: 7, data: { page_id: 7, admin__pages__tree_target: "row" })
    assert_selector "div#tree-row-1[data-tree-row][data-tree-title='Über uns'][data-tree-path='/de/ueber-uns'][data-tree-id='7'][data-page-id='7'][data-admin--pages--tree-target=row]"

    render_row
    assert_no_selector "[data-tree-path], [data-tree-id]"
    assert_no_selector "div.admin-tree-row__trailing"
  end

  test "the state stands 6px after the title, so a cut title's ellipsis never touches it" do
    render_row { |item| item.with_state { %(<span data-part="state"></span>).html_safe } }
    assert_selector ".admin-tree-row__title + .admin-tree-row__state > [data-part=state]"
    assert_match(/\.admin-tree-row__state\s*\{[^}]*margin-inline-start:\s*6px;/, stylesheet)

    render_row
    assert_no_selector ".admin-tree-row__state"
  end

  test "a parent's disclosure names the list it folds: a parent without controls is refused" do
    assert_raises(ArgumentError) { Admin::Ui::TreeItemComponent.new(id: "r", title: "A", parent: true) }
    assert_raises(ArgumentError) { Admin::Ui::TreeItemComponent.new(id: "r", title: "A", parent: true, controls: "") }
    assert_nothing_raised { Admin::Ui::TreeItemComponent.new(id: "r", title: "A", parent: true, flat: true) }
    assert_nothing_raised { Admin::Ui::TreeItemComponent.new(id: "r", title: "A", parent: true, controls: "tree-children-1") }
  end

  test "a screen cannot hand the row a class" do
    assert_raises(ArgumentError) { Admin::Ui::TreeItemComponent.new(id: "r", title: "A", data: { class: "font-bold" }) }
    assert_raises(ArgumentError) { Admin::Ui::TreeItemComponent.new(id: "r", title: "A", data: { "class" => "font-bold" }) }
    assert_raises(ArgumentError) { Admin::Ui::TreeItemComponent.new(id: "r", title: "A", class: "font-bold") }
  end

  test "a row is given its title" do
    assert_raises(ArgumentError) { render_inline(Admin::Ui::TreeItemComponent.new(id: "r", title: "A")) }
  end

  # "+" is the row's own part: the screen names it and hands it its address
  # and hooks, and the row draws its box and glyph; with no address it is a
  # button. A class from the screen is refused.
  test "the row's + is its own part, named by the screen, with no class of the screen's" do
    render_row { |item| item.with_add(label: "Add a page under About us", href: "/new?parent_id=1", data: { turbo_frame: "content" }) }
    add = page.find("div.admin-tree-row > a.admin-tree-row__add[href='/new?parent_id=1'][aria-label='Add a page under About us'][data-turbo-frame=content]")
    assert_equal [ "admin-tree-row__add" ], add[:class].split
    assert_equal %w[12 12 1.6], add.native.at_css("svg").then { |svg| [ svg["width"], svg["height"], svg["stroke-width"] ] }
    assert_equal "true", add.native.at_css("svg")["aria-hidden"]

    render_row { |item| item.with_add(label: "Add") }
    assert_selector "div.admin-tree-row > button.admin-tree-row__add[type=button][aria-label=Add]"

    assert_raises(ArgumentError) { render_row { |item| item.with_add(label: "Add", data: { class: "text-ink" }) } }
    assert_match(/\.admin-tree-row__add\s*\{[^}]*width:\s*20px;[^}]*height:\s*20px;[^}]*color:\s*var\(--cs-meta\);/, stylesheet)
    assert_match(/\.admin-tree-row__add:hover\s*\{\s*color:\s*var\(--cs-ink\);\s*\}/, stylesheet)
  end

  test "every CLASSES value is a class of the .admin-tree block" do
    css = stylesheet
    classes = Admin::Ui::TreeItemComponent::CLASSES
    assert classes.frozen?
    classes.each_value do |name|
      assert_match(/\.#{Regexp.escape(name)}(?![\w-])/, css, "#{name} is no class of the .admin-tree block in content-spiel.tailwind.css")
      assert name.start_with?("admin-tree"), "#{name} is the block's class, never a utility"
    end
  end
end
