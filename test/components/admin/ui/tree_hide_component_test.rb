require "test_helper"

# The tree column's hide button as the server draws it: a small tertiary icon
# button, the column's, drawn expanded, that the tree-width controller folds
# by, in the words of what the column holds. What a press does is a
# browser's to show (test/system/admin/tree_fold_test.rb).
class Admin::Ui::TreeHideComponentTest < ViewComponent::TestCase
  test "Hide page tree is a small tertiary icon button that controls the column, drawn expanded, and the controller's fold target" do
    render_inline(Admin::Ui::TreeHideComponent.new(subject: "pages"))

    button = page.find("button.admin-tree-hide[type=button]")
    assert_equal I18n.t("admin.components.shell.tree_subject.pages.hide"), button["aria-label"]
    assert_equal "Hide page tree", button["aria-label"]
    assert_equal "tree-column", button["aria-controls"]
    assert_equal "true", button["aria-expanded"]
    assert_equal "fold", button["data-admin--shell--tree-width-target"]
    assert_includes button["data-action"].split, "admin--shell--tree-width#fold"
    assert_includes button["class"], Admin::Ui::ButtonComponent.classes(:tertiary, size: :small)
    assert_selector "button.admin-tree-hide svg[aria-hidden=true]", count: 1
    assert_selector "button.admin-tree-hide [data-tooltip]", visible: :all, text: "Hide page tree"
  end

  test "the fold buttons, the divider and the top bar's tree button say what the column holds" do
    render_inline(Admin::Ui::TreeHideComponent.new(subject: "mind_graph"))

    assert_selector "button.admin-tree-hide[aria-label='Hide list']"
    assert_selector "button.admin-tree-hide [data-tooltip]", visible: :all, text: "Hide list"
    assert_raises(KeyError) { Admin::Ui::TreeHideComponent.new(subject: "posts") }
  end
end
