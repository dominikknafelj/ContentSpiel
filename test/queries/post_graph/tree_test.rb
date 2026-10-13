require "test_helper"

# `PostGraph::Tree`: the page tree as far as the viewer can read it, from
# plain rows. No statement, no record.
class PostGraph::TreeTest < ActiveSupport::TestCase
  #   1 Home
  #   ├─ 2 About (position 1)
  #   │   └─ 5 Team
  #   └─ 3 Blog (position 0)
  #   9 Stray: its parent, 8, is not among the rows
  ROWS = [ [ 9, 8, 0 ], [ 5, 2, 0 ], [ 2, 1, 1 ], [ 3, 1, 0 ], [ 1, nil, nil ] ].freeze

  setup { @tree = PostGraph::Tree.new(ROWS) }

  test "the order is Home, then each branch by position, and a page whose parent is not there comes after" do
    assert_equal 1, @tree.home_id
    assert_equal [ 1, 3, 2, 5, 9 ], @tree.order
    assert_equal [ 0, 1, 3 ], [ 1, 3, 5 ].map { |id| @tree.rank(id) }
  end

  test "depth 0 is Home, and a page whose parent is not there is at depth 1" do
    assert_equal({ 1 => 0, 3 => 1, 2 => 1, 5 => 2, 9 => 1 }, @tree.order.to_h { |id| [ id, @tree.depth(id) ] })
  end

  test "a parent that is not among the rows is no parent" do
    assert_nil @tree.parent(9)
    assert_nil @tree.parent(1)
    assert_equal 2, @tree.parent(5)
    assert_equal [ 3, 2 ], @tree.children(1)
    assert_equal [ 1, 5 ], @tree.neighbours(2)
    assert_empty @tree.neighbours(9)
  end

  test "siblings without a position come after those with one, by id" do
    tree = PostGraph::Tree.new([ [ 1, nil, nil ], [ 4, 1, nil ], [ 2, 1, nil ], [ 3, 1, 0 ] ])

    assert_equal [ 1, 3, 2, 4 ], tree.order
  end

  test "Home comes first whatever its id, and a page whose parent is not there after its whole tree" do
    tree = PostGraph::Tree.new([ [ 2, 9, 0 ], [ 7, nil, nil ], [ 8, 7, 0 ] ])

    assert_equal [ 7, [ 7, 8, 2 ] ], [ tree.home_id, tree.order ]
    assert_equal [ 0, 1, 1 ], [ 7, 8, 2 ].map { |id| tree.depth(id) }
  end

  test "no rows, and rows without Home" do
    assert_equal [ nil, [] ], [ PostGraph::Tree.new([]).home_id, PostGraph::Tree.new([]).order ]
    assert_equal [ nil, [ 5, 9 ] ], [ PostGraph::Tree.new([ [ 9, 8, 0 ], [ 5, 2, 0 ] ]).home_id, PostGraph::Tree.new([ [ 9, 8, 0 ], [ 5, 2, 0 ] ]).order ]
  end

  # The key is the one CS Studio's tree and the public branch sort by
  # (`PublicSite::Branch#in_tree_order`): the graph's order is theirs.
  test "siblings come in the order the Pages screen and the public menu give them" do
    home = root_page
    pages = 5.times.map { |index| create_page(title: "Sibling #{index}") }
    # Afterwards: creating a page renumbers its siblings.
    pages.zip([ 2, nil, 0, nil, 1 ]) { |page, position| page.update_columns(position: position) } # version: none (a test sets a position) # changes: none (a test sets a position)
    expected = pages.sort_by { |page| [ page.position.nil? ? 1 : 0, page.position.to_i, page.id ] }.map(&:id)

    tree = PostGraph::Tree.new(Page.pluck(:id, :parent_id, :position))

    assert_equal [ pages[2], pages[4], pages[0], pages[1], pages[3] ].map(&:id), expected
    assert_equal expected, tree.children(home.id)
  end
end
