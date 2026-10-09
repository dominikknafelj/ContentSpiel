require "test_helper"

class ContentBlocks::ReorderTest < ActiveSupport::TestCase
  test "ids that don't exactly match the page's blocks fail and change nothing" do
    page = create_page(title: "Page")
    a = page.content_blocks.create!(block_type: :rich_text, position: 0)
    b = page.content_blocks.create!(block_type: :rich_text, position: 1)

    result = ContentBlocks::Reorder.call(page, [ a.id, a.id ], actor: nil)

    assert_not result.ok?
    assert_equal [ 0, 1 ], [ a.reload.position, b.reload.position ]
  end

  test "writes positions 0..n-1 in the given order" do
    page = create_page(title: "Page")
    a = page.content_blocks.create!(block_type: :rich_text, position: 0)
    b = page.content_blocks.create!(block_type: :rich_text, position: 1)
    c = page.content_blocks.create!(block_type: :rich_text, position: 2)

    result = ContentBlocks::Reorder.call(page, [ c.id, a.id, b.id ], actor: nil)

    assert result.ok?
    assert_equal [ 1, 2, 0 ], [ a.reload.position, b.reload.position, c.reload.position ]
  end

  test "the page's own order lists its top-level blocks only" do
    page = create_page(title: "Page")
    text = page.content_blocks.create!(block_type: :rich_text, position: 0)
    section = page.content_blocks.create!(block_type: :section, position: 1)
    inside = page.content_blocks.create!(block_type: :rich_text, section: section, section_column: 1, position: 0)

    assert ContentBlocks::Reorder.call(page, [ section.id, text.id ], actor: nil).ok?
    assert_equal [ section, text ], page.content_blocks.top_level.reorder(:position).to_a
    assert_equal [ section.id, 1, 0 ], inside.reload.then { |block| [ block.section_id, block.section_column, block.position ] }
    assert_not ContentBlocks::Reorder.call(page, [ section.id, text.id, inside.id ], actor: nil).ok?
  end

  def banded_page
    page = create_page(title: "Moves")
    top = page.content_blocks.create!(block_type: :rich_text, position: 0)
    section = page.content_blocks.create!(block_type: :section, position: 1, settings: { "layout" => "two" })
    a = page.content_blocks.create!(block_type: :rich_text, section: section, section_column: 1, position: 0)
    b = page.content_blocks.create!(block_type: :rich_text, section: section, section_column: 1, position: 1)
    c = page.content_blocks.create!(block_type: :rich_text, section: section, section_column: 2, position: 0)
    [ page, top, section, a, b, c ]
  end

  def placement(block) = block.reload.then { |b| [ b.section_id, b.section_column, b.position ] }

  test "a column is reordered among its own blocks" do
    page, _top, section, a, b, c = banded_page

    assert ContentBlocks::Reorder.call(page, [ b.id, a.id ], section: section.id, column: 1, actor: nil).ok?
    assert_equal [ [ section.id, 1, 1 ], [ section.id, 1, 0 ], [ section.id, 2, 0 ] ], [ a, b, c ].map { |block| placement(block) }
  end

  test "a block moves from one column to another, and the column it left closes up" do
    page, _top, section, a, b, c = banded_page

    result = ContentBlocks::Reorder.call(page, [ a.id, c.id ], section: section.id, column: 2,
      moved_from: { a.id => { section_id: section.id, column: 1 } }, actor: nil)

    assert result.ok?
    assert_equal [ [ section.id, 2, 0 ], [ section.id, 1, 0 ], [ section.id, 2, 1 ] ], [ a, b, c ].map { |block| placement(block) }
  end

  test "a block moves out of a section into the page's list, and a top-level block into a column" do
    page, top, section, a, b, c = banded_page

    assert ContentBlocks::Reorder.call(page, [ top.id, section.id, a.id ], moved_from: { a.id => { section_id: section.id, column: 1 } }, actor: nil).ok?
    assert_equal [ nil, nil, 2 ], placement(a)
    assert_equal [ section.id, 1, 0 ], placement(b)

    assert ContentBlocks::Reorder.call(page, [ c.id, top.id ], section: section.id, column: 2, moved_from: { top.id => { section_id: "", column: "" } }, actor: nil).ok?
    assert_equal [ section.id, 2, 1 ], placement(top)
    assert_equal [ section, a ], page.content_blocks.top_level.reorder(:position).to_a
    assert_equal [ 0, 1 ], page.content_blocks.top_level.reorder(:position).pluck(:position)
  end

  test "a move is one event on the page, naming the section, the column and the block" do
    page, _top, section, a, _b, c = banded_page

    assert_difference -> { Audit::Event.where(action: "block.reordered").count }, 1 do
      ContentBlocks::Reorder.call(page, [ a.id, c.id ], section: section.id, column: 2, moved_from: { a.id => { section_id: section.id, column: 1 } }, actor: nil)
    end
    event = Audit::Event.where(action: "block.reordered").last
    assert_equal [ "Page", page.id ], [ event.subject_type, event.subject_id ]
    assert_equal({ "section_id" => section.id, "column" => 2, "moved_block_ids" => [ a.id ] }, event.metadata)
  end

  test "a block that is no longer where the caller thought is refused and nothing is written" do
    page, top, section, a, b, c = banded_page
    before = [ top, a, b, c ].map { |block| placement(block) }

    wrong_origin = ContentBlocks::Reorder.call(page, [ a.id, c.id ], section: section.id, column: 2, moved_from: { a.id => { section_id: nil, column: nil } }, actor: nil)
    unannounced = ContentBlocks::Reorder.call(page, [ a.id, c.id ], section: section.id, column: 2, actor: nil)
    incomplete = ContentBlocks::Reorder.call(page, [ a.id ], section: section.id, column: 2, moved_from: { a.id => { section_id: section.id, column: 1 } }, actor: nil)

    [ wrong_origin, unannounced, incomplete ].each do |result|
      assert_not result.ok?
      assert_not result.denied?
      assert_equal [ ContentBlocks::Reorder::STALE ], result.errors
    end
    assert_equal before, [ top, a, b, c ].map { |block| placement(block) }
  end

  test "a section that is gone, a column it no longer has and a section into a section are refused" do
    page, top, section, a, b, _c = banded_page
    other = page.content_blocks.create!(block_type: :section, position: 2)

    gone = ContentBlocks::Reorder.call(page, [ top.id ], section: 0, column: 1, moved_from: { top.id => { section_id: nil, column: nil } }, actor: nil)
    no_column = ContentBlocks::Reorder.call(page, [ top.id ], section: section.id, column: 3, moved_from: { top.id => { section_id: nil, column: nil } }, actor: nil)
    nested = ContentBlocks::Reorder.call(page, [ a.id, b.id, other.id ], section: section.id, column: 1,
      moved_from: { other.id => { section_id: nil, column: nil } }, actor: nil)

    assert_equal [ ContentBlocks::Reorder::NO_COLUMN ], gone.errors
    assert_equal [ ContentBlocks::Reorder::NO_COLUMN ], no_column.errors
    assert_equal [ ContentBlocks::Reorder::NESTED ], nested.errors
    assert_nil other.reload.section_id
    assert_nil top.reload.section_id
  end

  test "another page's block is never moved in" do
    page, _top, section, a, = banded_page
    foreign = create_page(title: "Elsewhere").content_blocks.create!(block_type: :rich_text, position: 0)

    result = ContentBlocks::Reorder.call(page, [ a.id, foreign.id ], section: section.id, column: 1,
      moved_from: { foreign.id => { section_id: nil, column: nil } }, actor: nil)

    assert_not result.ok?
    assert_nil foreign.reload.section_id
  end

  # One order of locks for every write to a page's blocks: the page's row,
  # then block rows (`ContentBlocks::Save#call` has the deadlock a second
  # order made). A reorder was the last writer that went block-first -- it
  # wrote positions and then touched the page -- so EVERY reorder takes the
  # lock first: the plain top-level one that names no section too.
  test "every reorder locks the page's row before it reads or writes a block: top level, a column, a move" do
    page, top, section, a, b, c = banded_page
    calls = [
      -> { ContentBlocks::Reorder.call(page, [ section.id, top.id ], actor: nil) },
      -> { ContentBlocks::Reorder.call(page, [ b.id, a.id ], section: section.id, column: 1, actor: nil) },
      -> { ContentBlocks::Reorder.call(page, [ c.id, a.id ], section: section.id, column: 2, moved_from: { a.id => { section_id: section.id, column: 1 } }, actor: nil) }
    ]

    calls.each do |call|
      statements = capture_sql { assert call.call.ok? }
      lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
      block = statements.index { |sql| sql.include?('"content_blocks"') }

      assert_not_nil lock
      assert_operator lock, :<, block
      assert_equal 1, statements.count { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
    end
  end

  # A refused call wrote nothing, and it is judged under the lock: what it
  # read is what the other tab committed.
  test "a refused reorder has taken the page's lock before it looked, and writes nothing" do
    page, top, section, = banded_page

    statements = capture_sql do
      assert_not ContentBlocks::Reorder.call(page, [ top.id ], section: section.id, column: 3, moved_from: { top.id => { section_id: nil, column: nil } }, actor: nil).ok?
    end

    assert_operator statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }, :<, statements.index { |sql| sql.include?('"content_blocks"') }
    assert_empty statements.grep(/\A(UPDATE|INSERT|DELETE)/)
  end

  # The plan's review focus for this task. Two tabs on one page: one folds a
  # three-column section to two while the other, whose screen still shows
  # three lanes, drops a block into the third. The page's lock makes them
  # take turns; whichever order they land in, no block ends in a column the
  # section doesn't have.
  test "a drop into the last column after another tab folded it away is refused with a message" do
    page = create_page(title: "Two tabs")
    section = page.content_blocks.create!(block_type: :section, position: 0, settings: { "layout" => "three" })
    in_third = page.content_blocks.create!(block_type: :rich_text, section: section, section_column: 3, position: 0)
    dropped = page.content_blocks.create!(block_type: :rich_text, position: 1)
    drop = -> { ContentBlocks::Reorder.call(page, [ in_third.id, dropped.id ], section: section.id, column: 3, moved_from: { dropped.id => { section_id: nil, column: nil } }, actor: nil) }

    # The fold first: the drop is refused, and the block stays where it was.
    assert ContentBlocks::Save.call(ContentBlock.find(section.id), attributes: { settings: { "layout" => "two" } }, actor: nil).ok?
    refused = drop.call

    assert_equal [ ContentBlocks::Reorder::NO_COLUMN ], refused.errors
    assert_not refused.denied?
    assert_equal [ nil, nil, 1 ], placement(dropped)
    assert_equal [ section.id, 2, 0 ], placement(in_third)
    assert_empty page.content_blocks.where(section_column: 3..)

    # The drop first: the fold that follows takes the dropped block along.
    assert ContentBlocks::Save.call(ContentBlock.find(section.id), attributes: { settings: { "layout" => "three" } }, actor: nil).ok?
    assert ContentBlocks::Reorder.call(page, [ dropped.id ], section: section.id, column: 3, moved_from: { dropped.id => { section_id: nil, column: nil } }, actor: nil).ok?
    assert ContentBlocks::Save.call(ContentBlock.find(section.id), attributes: { settings: { "layout" => "two" } }, actor: nil).ok?

    assert_equal [ [ section.id, 2, 0 ], [ section.id, 2, 1 ] ], [ in_third, dropped ].map { |block| placement(block) }
    assert_empty page.content_blocks.where(section_column: 3..)
  end

  test "a move bumps the page and leaves the moved block's own updated_at alone" do
    page, _top, section, a, _b, c = banded_page
    backdated = 1.hour.ago.change(usec: 0)
    page.update_columns(updated_at: backdated)
    a.update_columns(updated_at: backdated)

    assert ContentBlocks::Reorder.call(page, [ a.id, c.id ], section: section.id, column: 2, moved_from: { a.id => { section_id: section.id, column: 1 } }, actor: nil).ok?

    assert_operator page.reload.updated_at, :>, backdated
    assert_equal backdated, a.reload.updated_at
  end

  test "a move that changes nothing a second time is refused as stale, not repeated" do
    page, _top, section, a, _b, c = banded_page
    move = -> { ContentBlocks::Reorder.call(page, [ a.id, c.id ], section: section.id, column: 2, moved_from: { a.id => { section_id: section.id, column: 1 } }, actor: nil) }

    assert move.call.ok?
    assert_equal [ ContentBlocks::Reorder::STALE ], move.call.errors
  end

  # What a forged request can put where a hash belongs: read as "the top
  # level", which the block is then found at or not.
  test "a malformed moved_from is judged like any other, never an exception" do
    page, top, section, _a, _b, c = banded_page

    assert_equal [ ContentBlocks::Reorder::STALE ],
      ContentBlocks::Reorder.call(page, [ c.id, top.id ], section: section.id, column: 2, moved_from: { "x" => "y" }, actor: nil).errors
    assert ContentBlocks::Reorder.call(page, [ c.id, top.id ], section: section.id, column: 2, moved_from: { top.id.to_s => "top" }, actor: nil).ok?
    assert_equal [ section.id, 2, 1 ], placement(top)
  end
end
