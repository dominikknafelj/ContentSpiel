require "test_helper"

# The folded column's strip as the server draws it: one icon button, the
# column's, that the tree-width controller unfolds by, in the words of what
# the column holds. What it does is a browser's to show
# (`test/system/admin/tree_fold_test.rb`).
class Admin::Shell::TreeFoldComponentTest < ViewComponent::TestCase
  test "Show page tree is a small tertiary icon button that controls the column, drawn collapsed, and the controller's unfold target" do
    render_inline(Admin::Shell::TreeFoldComponent.new(subject: "pages"))

    button = page.find("button.admin-tree-fold[type=button]", visible: :all)
    assert_equal I18n.t("admin.components.shell.tree_subject.pages.show"), button["aria-label"]
    assert_equal "Show page tree", button["aria-label"]
    assert_equal "tree-column", button["aria-controls"]
    assert_equal "false", button["aria-expanded"]
    assert_equal "unfold", button["data-admin--shell--tree-width-target"]
    assert_includes button["data-action"].split, "admin--shell--tree-width#unfold"
    assert_includes button["class"], Admin::Ui::ButtonComponent.classes(:tertiary, size: :small)
    assert_selector "button.admin-tree-fold svg[aria-hidden=true]", visible: :all, count: 1
    assert_selector "button.admin-tree-fold [data-tooltip]", visible: :all, text: "Show page tree"
  end

  test "the fold buttons, the divider and the top bar's tree button say what the column holds" do
    render_inline(Admin::Shell::TreeFoldComponent.new(subject: "mind_graph"))

    assert_selector "button.admin-tree-fold[aria-label='Show list']", visible: :all
    assert_selector "button.admin-tree-fold [data-tooltip]", visible: :all, text: "Show list"
    assert_raises(KeyError) { Admin::Shell::TreeFoldComponent.new(subject: "posts") }
  end
end
