require "test_helper"

class BlockOutlineTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Outline")
    @intro = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @section = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "three" })
    @outro = @page.content_blocks.create!(block_type: "rich_text", position: 2)
    @b = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    @a = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 0)
    @c = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 3, position: 0)
    @outline = BlockOutline.new(@page.content_blocks.reload)
  end

  test "top level is the blocks outside any section, in position order" do
    assert_equal [ @intro, @section, @outro ], @outline.top_level
    assert_equal [ @section ], @outline.sections
  end

  test "a section's columns are one array per column of its layout, an empty one kept" do
    assert_equal [ [ @a, @b ], [], [ @c ] ], @outline.columns(@section)
    assert_equal [], @outline.columns(@intro)
  end

  test "reading order goes column by column inside a section" do
    assert_equal [ @a, @b, @c ], @outline.blocks_in(@section)
    assert_equal [ @intro, @section, @a, @b, @c, @outro ], @outline.reading_order
  end

  test "a block beyond the layout's last column is still in the section's blocks" do
    @section.update_columns(settings: { "layout" => "one" })
    outline = BlockOutline.new(@page.content_blocks.reload)
    section = outline.top_level.second

    assert_equal [ [ @a, @b ] ], outline.columns(section)
    assert_equal [ @a, @b, @c ], outline.blocks_in(section)
  end

  test "it reads the section of each block without a query" do
    blocks = @page.content_blocks.reload.to_a
    outline = BlockOutline.new(blocks)

    assert_empty capture_sql { outline.reading_order.each(&:section) }
  end
end
