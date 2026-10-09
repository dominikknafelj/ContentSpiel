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
end
