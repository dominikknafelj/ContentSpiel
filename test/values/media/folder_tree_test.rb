require "test_helper"

class Media::FolderTreeTest < ActiveSupport::TestCase
  test "the tree is one query and sorts names case-insensitively with numbers as numbers" do
    Media::Folder.create!(name: "Event 10")
    Media::Folder.create!(name: "event 2")
    Media::Folder.create!(name: "Alpha")

    tree = nil
    assert_queries_count(1) { tree = Media::FolderTree.load }

    assert_equal [ "Alpha", "event 2", "Event 10" ], tree.roots.map(&:name)
    assert_equal 3, tree.size
  end

  test "siblings that compare equal in natural order fall back to the id" do
    nodes = [ Media::FolderTree::Node.new(9, nil, "a01"), Media::FolderTree::Node.new(3, nil, "a1") ]

    assert_equal [ 3, 9 ], Media::FolderTree.new(nodes).roots.map(&:id)
    assert_equal [ 3, 9 ], Media::FolderTree.new(nodes.reverse).roots.map(&:id)
  end

  test "depth, height, path and descendants" do
    a = Media::Folder.create!(name: "A")
    b = Media::Folder.create!(name: "B", parent: a)
    c = Media::Folder.create!(name: "C", parent: b)
    d = Media::Folder.create!(name: "D", parent: c)
    other = Media::Folder.create!(name: "Other")
    tree = Media::FolderTree.load

    assert_equal [ 1, 2, 3, 4 ], [ a, b, c, d ].map { |folder| tree.depth(folder.id) }
    assert_equal [ 4, 3, 2, 1 ], [ a, b, c, d ].map { |folder| tree.height(folder.id) }
    assert_equal %w[A B C D], tree.path(d.id).map(&:name)
    assert_equal "A / B / C", tree.path_name(c.id)
    assert_equal [ b.id, c.id, d.id ].sort, tree.descendant_ids(a.id).sort
    assert_equal [], tree.descendant_ids(d.id)
    assert_equal [ b.id ], tree.children(a.id).map(&:id)
    assert_equal [ a.id, other.id ].sort, tree.roots.map(&:id).sort
    assert_equal b.id, tree.find(b.id).id
    assert_nil tree.find(0)
    assert_equal [ a, b, c, d, other ].map(&:id).sort, tree.ids.sort
    assert_equal [ [ "A", 1 ], [ "B", 2 ], [ "C", 3 ], [ "D", 4 ], [ "Other", 1 ] ],
      tree.each_in_order.map { |node, depth| [ node.name, depth ] }
  end

  test "inside? is true for a folder under another and for itself" do
    a = Media::Folder.create!(name: "A")
    b = Media::Folder.create!(name: "B", parent: a)
    other = Media::Folder.create!(name: "Other")
    tree = Media::FolderTree.load

    assert tree.inside?(b.id, of: a.id)
    assert tree.inside?(a.id, of: a.id)
    assert_not tree.inside?(a.id, of: b.id)
    assert_not tree.inside?(b.id, of: other.id)
  end
end
