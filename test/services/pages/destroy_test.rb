require "test_helper"

class Pages::DestroyTest < ActiveSupport::TestCase
  test "refuses the root and pages with children, deletes leaves" do
    parent = create_page(title: "Parent")
    leaf = create_page(title: "Leaf", parent: parent)

    assert_not Pages::Destroy.call(root_page, actor: nil).ok?
    result = Pages::Destroy.call(parent, actor: nil)
    assert_not result.ok?
    assert_includes result.errors, "cannot delete a page that still has children"

    assert Pages::Destroy.call(leaf, actor: nil).ok?
    assert_not Page.exists?(leaf.id)
  end
end
