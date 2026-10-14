require "test_helper"

# The page tree's divider as the server draws it (Claude Design, 2026-10-13,
# T1): a focusable separator that says its width, with the shared tooltip and
# the numbers its script works with. What it does is a browser's to show
# (`test/system/admin/tree_column_test.rb`).
class Admin::Shell::TreeDividerComponentTest < ViewComponent::TestCase
  Divider = Admin::Shell::TreeDividerComponent

  test "a vertical separator in the Tab order that says the default width between the minimum and the maximum, by name" do
    render_inline(Divider.new)

    assert_selector "div.admin-tree-divider[role=separator][aria-orientation=vertical][tabindex='0'][aria-controls=tree-column]", count: 1
    assert_selector "[role=separator][aria-valuenow='272'][aria-valuemin='220'][aria-valuemax='480']"
    assert_selector "[role=separator][aria-label='#{I18n.t("admin.components.shell.tree_divider.label")}']"
    assert_equal "Page tree width", I18n.t("admin.components.shell.tree_divider.label")
  end

  test "the numbers are the design's, and the default is the 17rem the column always was" do
    assert_equal [ 220, 272, 480, 640, 240, 400 ], [ Divider::MIN, Divider::DEFAULT, Divider::MAX, Divider::EDITOR, Divider::SIDEBAR, Divider::NOTES ]
    assert_equal 17 * 16, Divider::DEFAULT
    # The design's own sum: at the default the tree stays beside the notes from a 1552px window.
    assert_equal 1552, Divider::SIDEBAR + Divider::DEFAULT + Divider::NOTES + Divider::EDITOR
  end

  test "the script is handed every number and the storage key as values, and the tooltip's sentence as a message" do
    render_inline(Divider.new)
    divider = page.find("[role=separator]")

    assert_equal %w[admin--ui--tooltip admin--shell--tree-width], divider["data-controller"].split
    { min: 220, default: 272, max: 480, editor: 640, sidebar: 240, notes: 400, key: "cs-tree-width" }.each do |name, value|
      assert_equal value.to_s, divider["data-admin--shell--tree-width-#{name}-value"], name.to_s
    end
    messages = JSON.parse(divider["data-messages"])
    assert_equal "Tree width %{width}px. Arrow keys to resize.", messages.fetch("components.shell.tree_divider.tooltip")
  end

  test "every gesture has its action: the press that begins a drag, a double click, the keys, and what keeps the values current" do
    render_inline(Divider.new)
    actions = page.find("[role=separator]")["data-action"].split

    %w[pointerdown->admin--shell--tree-width#press pointerenter->admin--shell--tree-width#enter pointerleave->admin--shell--tree-width#leave
       dblclick->admin--shell--tree-width#reset keydown->admin--shell--tree-width#key
       resize@window->admin--shell--tree-width#sync turbo:before-cache@document->admin--shell--tree-width#rest].each do |action|
      assert_includes actions, action
    end
    # The shared tooltip's own, unchanged: the divider is its host.
    Admin::Ui::TooltipComponent::ACTIONS.split.each { |action| assert_includes actions, action }
  end

  test "the shared tooltip is inside, hidden until asked for, and names the default width" do
    render_inline(Divider.new)

    assert_selector "[role=separator] .admin-tree-divider__tip [data-tooltip][data-admin--ui--tooltip-target=bubble]", visible: :all, count: 1,
      text: "Tree width 272px. Arrow keys to resize."
    assert page.find("[data-tooltip]", visible: :all)["hidden"]
  end
end
