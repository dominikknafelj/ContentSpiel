require "test_helper"

class Admin::GroupsScreen::BranchTreeTest < ViewComponent::TestCase
  include ContentHelper

  test "a root chosen below another chosen root is implied and still remembered as chosen" do
    top = create_page(title: "Top")
    child = create_page(title: "Child", parent: top)
    other = create_page(title: "Other")
    tree = Admin::GroupsScreen::BranchTree.new(pages: [ top, child, other ], readable: [ top.id, child.id, other.id ].to_set, context_only: Set.new, locale: "en")

    states = tree.states([ top.id, child.id ])

    assert_equal :chosen, states[top.id].state
    assert_equal :implied, states[child.id].state
    assert states[child.id].chosen
    assert_equal :none, states[other.id].state
  end
end
