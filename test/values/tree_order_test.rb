require "test_helper"

# The one rule for the order of a page's children (`app/values/tree_order.rb`):
# by position, a page without one last, then by id. The four places that
# sort siblings in Ruby (the public branch, CS Studio's tree, the New page
# dialog's list and the mind graph's tree) ask it, and each has its own test
# that it does, over real pages; this file holds the rule itself.
class TreeOrderTest < ActiveSupport::TestCase
  Row = Struct.new(:id, :position)

  test "siblings come by position, one without a position last, and by id within one position" do
    rows = [ Row.new(7, 2), Row.new(3, nil), Row.new(9, 0), Row.new(1, nil), Row.new(5, 1), Row.new(4, 1), Row.new(2, 0) ]

    assert_equal [ 2, 9, 4, 5, 7, 1, 3 ], TreeOrder.sort(rows).map(&:id)
    assert_equal [ 2, 9, 4, 5, 7, 1, 3 ], rows.map { |row| [ row.id, row.position ] }.sort_by { |id, position| TreeOrder.key(position, id) }.map(&:first)
  end

  test "a position of zero is a position: it comes first, not with the pages that have none" do
    assert_equal(-1, TreeOrder.key(0, 9) <=> TreeOrder.key(nil, 1))
    assert_equal(-1, TreeOrder.key(1_000_000, 9) <=> TreeOrder.key(nil, 1))
    assert_equal(-1, TreeOrder.key(nil, 1) <=> TreeOrder.key(nil, 2))
  end

  test "a negative position sorts before zero, as Postgres orders the column" do
    assert_equal [ 3, 1, 2 ], TreeOrder.sort([ Row.new(1, 0), Row.new(2, nil), Row.new(3, -1) ]).map(&:id)
  end

  test "sort answers a new list and leaves the one it was handed as it was" do
    rows = [ Row.new(2, 1), Row.new(1, 0) ]

    assert_equal [ 1, 2 ], TreeOrder.sort(rows).map(&:id)
    assert_equal [ 2, 1 ], rows.map(&:id)
    assert_empty TreeOrder.sort([])
  end

  # The order is Postgres' own for `ORDER BY position, id` (a NULL last),
  # which is what closure_tree's `order: "position"` gives the public menu.
  test "the order is the database's own for ORDER BY position, id" do
    pages = 6.times.map { |index| create_page(title: "Ordered #{index}") }
    pages.zip([ 2, nil, 0, nil, 1, 1 ]) { |page, position| page.update_columns(position: position) } # version: none (a test sets a position) # changes: none (a test sets a position)
    ids = pages.map(&:id)

    assert_equal Page.where(id: ids).order(:position, :id).pluck(:id), TreeOrder.sort(Page.where(id: ids).to_a.shuffle(random: Random.new(3))).map(&:id)
  end

  # THE KEY IS WRITTEN ONCE. It was written four times, each a copy of the
  # last with a comment naming the others, and the fifth copy was a test's.
  # A second writing does not fail anything by itself: it fails the day one
  # of them is changed. So the idiom of the key (a nil test of a position
  # turned into 1 or 0, or a position made a number with `to_i` inside a
  # sort) is refused everywhere in `app` and `lib` but in the value's file.
  IDIOM = /position\S*\.nil\?\s*\?\s*1\s*:\s*0|sort(?:_by)?!?\s*(?:\{|do)[^\n]*position\S*\.to_i|sort_by!?\(&:position\)/
  HOME = "app/values/tree_order.rb".freeze

  test "the key of the tree's order is written in app/values/tree_order.rb and nowhere else" do
    files = Dir[Rails.root.join("{app,lib}/**/*.{rb,erb,rake}")]
    written = files.flat_map do |file|
      File.readlines(file).each_with_index.filter_map { |line, index| "#{Pathname(file).relative_path_from(Rails.root)}:#{index + 1}" if line.match?(IDIOM) }
    end

    assert_operator files.size, :>, 300, "the guard reads the application's files"
    assert_equal [ HOME ], written.map { |place| place.split(":").first }.uniq, written.join("\n")
  end

  test "the guard can fail: each form the key was written in is one it reads, and the allowed uses of a position are not" do
    [
      "pages.sort_by { |page| [ page.position.nil? ? 1 : 0, page.position.to_i, page.id ] }",
      "ids.sort_by! { |id| [ position[id].nil? ? 1 : 0, position[id].to_i, id ] }",
      "children.sort_by { |child| child.position.to_i }",
      "children.sort_by(&:position)"
    ].each { |line| assert_match IDIOM, line }
    [
      "chain.map { |page| page.position.to_i }",
      "@page, @parent, @position, @actor = page, parent, position.to_i, actor",
      "TreeOrder.sort(pages)"
    ].each { |line| assert_no_match IDIOM, line }
  end

  test "the four that order siblings in Ruby ask the one rule" do
    %w[
      app/queries/public_site/branch.rb
      app/components/admin/pages_screen/tree_node_component.rb
      app/components/admin/editor_screen/new_page_form_component.rb
      app/queries/post_graph/tree.rb
    ].each { |file| assert_match(/TreeOrder\.(?:sort|key)\b/, Rails.root.join(file).read, file) }
  end
end
