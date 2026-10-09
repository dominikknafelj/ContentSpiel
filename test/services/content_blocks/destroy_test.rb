require "test_helper"

class ContentBlocks::DestroyTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Destroy")
    @before = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @section = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "two" })
    @after = @page.content_blocks.create!(block_type: "rich_text", position: 2)
    @right = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 2, position: 0, media_asset: create_media_asset)
    @left_b = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    @left_a = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 0)
    Media::UsageIndex.refresh(@right)
  end

  test "a section is deleted with its blocks, as one event naming them" do
    assert_difference -> { ContentBlock.count } => -4, -> { Audit::Event.where(action: "block.deleted").count } => 1 do
      assert ContentBlocks::Destroy.call(@section, actor: nil).ok?
    end

    assert_equal [ @before, @after ], @page.content_blocks.reload.to_a
    assert_equal [ @left_a.id, @left_b.id, @right.id ], Audit::Event.where(action: "block.deleted").last.metadata["deleted_block_ids"]
    assert_empty Media::Usage.where(owner_type: "ContentBlock", owner_id: @right.id)
  end

  test "keep_blocks lifts the blocks to the section's place in reading order, then removes the section" do
    assert_difference -> { ContentBlock.count } => -1, -> { Audit::Event.where(action: "block.deleted").count } => 1 do
      assert ContentBlocks::Destroy.call(@section, keep_blocks: true, actor: nil).ok?
    end

    top = @page.content_blocks.top_level.reorder(:position).to_a
    assert_equal [ @before, @left_a, @left_b, @right, @after ], top
    assert_equal [ 0, 1, 2, 3, 4 ], top.map(&:position)
    assert top.all? { |block| block.section_id.nil? && block.section_column.nil? }
    assert_equal [ @left_a.id, @left_b.id, @right.id ], Audit::Event.where(action: "block.deleted").last.metadata["kept_block_ids"]
    assert_equal 1, Media::Usage.where(owner_type: "ContentBlock", owner_id: @right.id).count
  end

  test "an empty section, a block in a section and a top-level block are deleted as before" do
    empty = @page.content_blocks.create!(block_type: "section", position: 3)

    assert ContentBlocks::Destroy.call(empty, keep_blocks: true, actor: nil).ok?
    assert ContentBlocks::Destroy.call(@left_a, actor: nil).ok?
    assert ContentBlocks::Destroy.call(@before, actor: nil).ok?
    assert_equal [ @left_b, @right ], @section.section_blocks.reload.to_a
    assert_equal({}, Audit::Event.where(action: "block.deleted").last.metadata)
  end

  test "a live page's version moves when a section is deleted either way" do
    @page.update!(published_at: 1.day.ago)

    assert_changes -> { PublicSite.content_version } do
      ContentBlocks::Destroy.call(@section, keep_blocks: true, actor: nil)
    end
  end

  test "the positions the deleted block leaves are closed up in its own container only" do
    assert ContentBlocks::Destroy.call(@left_a, actor: nil).ok?
    assert_equal [ [ @left_b.id, 1, 0 ], [ @right.id, 2, 0 ] ], @section.section_blocks.reload.map { |block| [ block.id, block.section_column, block.position ] }

    assert ContentBlocks::Destroy.call(@section, actor: nil).ok?
    assert_equal [ [ @before.id, 0 ], [ @after.id, 1 ] ], @page.content_blocks.reload.reorder(:position).pluck(:id, :position)
  end

  test "a section's delete locks the page's row before it reads the blocks in it" do
    statements = capture_sql { assert ContentBlocks::Destroy.call(@section, actor: nil).ok? }
    lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
    read = statements.index { |sql| sql.match?(/FROM "content_blocks".*"section_id" = /m) }

    assert_operator lock, :<, read
    assert_nil capture_sql { assert ContentBlocks::Destroy.call(@before, actor: nil).ok? }.index { |sql| sql.include?("FOR UPDATE") }
  end

  test "a section's delete is refused whole for an actor without the page's edit right" do
    @page.update!(published_at: nil)
    nobody = User.create!(email_address: "nobody-destroy@example.com", password: "a long enough password")

    assert_no_difference -> { ContentBlock.count } do
      assert_predicate as(nobody) { ContentBlocks::Destroy.call(@section, keep_blocks: true) }, :denied?
      assert_predicate as(nobody) { ContentBlocks::Destroy.call(@section) }, :denied?
    end
    assert_equal 3, @section.section_blocks.reload.size
  end
end
