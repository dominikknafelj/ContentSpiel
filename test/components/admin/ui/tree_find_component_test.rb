require "test_helper"

# The tree's find field as the server draws it: a search landmark, its label,
# the tree it names and its words. What typing does is the script's
# (test/system/admin/tree_find_test.rb).
class Admin::Ui::TreeFindComponentTest < ViewComponent::TestCase
  def messages = JSON.parse(page.find("[role=search]")["data-messages"])

  test "a search landmark with a real label, aria-controls naming the tree and / as its shortcut" do
    render_inline(Admin::Ui::TreeFindComponent.new(controls: "tree-list"))

    assert_selector "div[role=search][data-controller='admin--tree--find']"
    assert_selector "div[role=search] label.sr-only[for='tree-list-find']", text: "Find a page", exact_text: true
    assert_selector "input#tree-list-find[type=search][aria-controls='tree-list'][aria-keyshortcuts='/'][autocomplete=off][placeholder='Find a page'].admin-well"
    assert_selector "input#tree-list-find[data-admin--tree--find-target=field]"
    assert_selector "kbd[aria-hidden=true][data-admin--tree--find-target=hint]", text: "/", exact_text: true
    assert_selector "button[hidden][aria-label=Clear][data-admin--tree--find-target=clear][data-action~='admin--tree--find#clear']", visible: :all
    assert_selector "p[role=status][aria-live=polite][data-admin--tree--find-target=status]:empty", visible: :all
  end

  test "the nouns pick their words" do
    render_inline(Admin::Ui::TreeFindComponent.new(controls: "tree-list", noun: :pages))
    assert_selector "label", text: "Find a page", exact_text: true
    assert_equal({ "one" => "1 page matches", "other" => "%{count} pages match" }, messages["components.ui.tree_find.count.pages"])
    assert_equal "No pages match", messages["components.ui.tree_find.none.pages"]
    assert_equal "pages", page.find("[role=search]")["data-admin--tree--find-noun-value"]

    render_inline(Admin::Ui::TreeFindComponent.new(controls: "mind-graph-tree", noun: :nodes))
    assert_selector "label[for='mind-graph-tree-find']", text: "Find a page, post or tag", exact_text: true
    assert_selector "input[placeholder='Find a page, post or tag'][aria-controls='mind-graph-tree']"
    assert_equal({ "one" => "1 match", "other" => "%{count} matches" }, messages["components.ui.tree_find.count.nodes"])
    assert_equal "Nothing matches", messages["components.ui.tree_find.none.nodes"]
    assert_not messages.key?("components.ui.tree_find.count.pages"), "a noun's field carries its own words only"

    assert_raises(ArgumentError) { Admin::Ui::TreeFindComponent.new(controls: "tree-list", noun: :posts) }
    assert_raises(ArgumentError) { Admin::Ui::TreeFindComponent.new(controls: "") }
  end

  test "Clear the search to move pages is offered only where the tree moves" do
    render_inline(Admin::Ui::TreeFindComponent.new(controls: "tree-list", moving: true))
    assert_equal "Clear the search to move pages", messages["components.ui.tree_find.no_moving"]
    assert_equal "true", page.find("[role=search]")["data-admin--tree--find-moving-value"]

    render_inline(Admin::Ui::TreeFindComponent.new(controls: "mind-graph-tree", noun: :nodes))
    assert_not messages.key?("components.ui.tree_find.no_moving")
    assert_equal "false", page.find("[role=search]")["data-admin--tree--find-moving-value"]
  end

  test "a field that keeps its query across the content frame's navigation says so to its script" do
    render_inline(Admin::Ui::TreeFindComponent.new(controls: "mind-graph-tree", noun: :nodes, keep_across_frames: true))
    assert_equal "true", page.find("[role=search]")["data-admin--tree--find-keep-value"]
    assert_includes page.find("[role=search]")["data-action"], "turbo:frame-load@document->admin--tree--find#frameLoaded"

    render_inline(Admin::Ui::TreeFindComponent.new(controls: "tree-list", noun: :pages))
    assert_equal "false", page.find("[role=search]")["data-admin--tree--find-keep-value"]
  end
end
