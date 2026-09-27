require "test_helper"

class Pages::MoveTest < ActiveSupport::TestCase
  test "moves a page to a rank under a new parent" do
    a = create_page(title: "A")
    b = create_page(title: "B")
    c = create_page(title: "C", parent: a)

    result = Pages::Move.call(c, parent: root_page, position: 0, actor: nil)
    assert result.ok?
    assert_equal [ c, a, b ], root_page.children.reload.to_a
    assert_equal "/c", c.full_path("en")
  end

  test "refuses the root and moves under itself or a descendant" do
    a = create_page(title: "A")
    child = create_page(title: "Child", parent: a)

    assert_not Pages::Move.call(root_page, parent: a, position: 0, actor: nil).ok?
    assert_not Pages::Move.call(a, parent: child, position: 0, actor: nil).ok?
    assert_not Pages::Move.call(a, parent: a, position: 0, actor: nil).ok?
  end

  test "an out-of-range position is clamped" do
    a = create_page(title: "A")
    create_page(title: "B")
    assert Pages::Move.call(a, parent: root_page, position: 99, actor: nil).ok?
    assert_equal "B", root_page.children.reload.first.title
  end
end
