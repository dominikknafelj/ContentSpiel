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

  test "the deleted block's event names its page" do
    assert ContentBlocks::Destroy.call(@after, actor: nil).ok?

    assert_equal @page.id, Audit::Event.where(action: "block.deleted").last.metadata["page_id"]
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
    assert_equal({ "page_id" => @page.id }, Audit::Event.where(action: "block.deleted").last.metadata)
  end

  test "a live page's version moves when a section is deleted either way" do
    @page.update!(published_at: 1.day.ago)
    follow_rows! # setup fix: the page was made live through the service and has a copy; this one is served from its rows

    assert_changes -> { PublicSite.content_version } do
      ContentBlocks::Destroy.call(@section, keep_blocks: true, actor: nil)
    end
  end

  test "a live page that has a copy keeps its version when a section is deleted either way" do
    assert @page.reload.live?
    assert copied?(@page)

    assert_no_changes -> { PublicSite.content_version } do
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
  end

  # The same order as every other write of a block:
  # the page's row, then the block's. A lift and the renumbering after a
  # section's delete write top-level blocks under that lock, so a top-level
  # block's delete takes it first too; in a section it also keeps the
  # renumbering of the column from racing a fold into it.
  test "a delete of a block locks the page's row before it deletes the block, in a section and at the top level" do
    [ @left_a, @before ].each do |block|
      statements = capture_sql { assert ContentBlocks::Destroy.call(block, actor: nil).ok? }
      lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
      delete = statements.index { |sql| sql.start_with?('DELETE FROM "content_blocks"') }

      assert_operator lock, :<, delete
      assert_equal 1, statements.count { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
    end
  end

  test "a lift writes only the rows that move: the blocks before the section are left alone" do
    statements = capture_sql { assert ContentBlocks::Destroy.call(@section, keep_blocks: true, actor: nil).ok? }

    # The three lifted blocks, the section pushed behind them and the block
    # after it; then that last one again when the section's gap is closed.
    assert_equal 6, statements.count { |sql| sql.start_with?('UPDATE "content_blocks"') }
    assert_equal [ @before, @left_a, @left_b, @right, @after ], @page.content_blocks.top_level.reorder(:position).to_a
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

  # A section whose type is no longer registered is no `container?`, and still
  # holds its blocks (sections spec §6): what a delete takes along, or lifts,
  # is decided from the rows. Before, its blocks were not looked for and the
  # section's own delete ran into the foreign key.
  test "a section whose type is gone is still deleted with its blocks" do
    @section.update_columns(block_type: "gone/section")

    assert_difference -> { ContentBlock.count } => -4, -> { Audit::Event.where(action: "block.deleted").count } => 1 do
      assert ContentBlocks::Destroy.call(@section.reload, actor: nil).ok?
    end
    assert_equal [ @left_a.id, @left_b.id, @right.id ], Audit::Event.where(action: "block.deleted").last.metadata["deleted_block_ids"]
    assert_equal [ [ @before.id, 0 ], [ @after.id, 1 ] ], @page.content_blocks.reload.reorder(:position).pluck(:id, :position)
  end

  test "a section whose type is gone is removed with its blocks kept, lifted to its place" do
    @section.update_columns(block_type: "gone/section")

    assert_difference -> { ContentBlock.count }, -1 do
      assert ContentBlocks::Destroy.call(@section.reload, keep_blocks: true, actor: nil).ok?
    end
    top = @page.content_blocks.top_level.reorder(:position).to_a
    assert_equal [ @before, @left_a, @left_b, @right, @after ], top
    assert_equal [ 0, 1, 2, 3, 4 ], top.map(&:position)
    assert_equal [ @left_a.id, @left_b.id, @right.id ], Audit::Event.where(action: "block.deleted").last.metadata["kept_block_ids"]
  end

  def noted_section
    page = create_page(title: "Noted", published: false)
    section = page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    inside = page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    as(users(:two)) { [ page, section, inside ].each { |subject| Notes::Start.call(subject, body: "A note") } }
    [ page, section, inside ]
  end

  test "deleting a block deletes its notes and leaves the page's" do
    page = create_page(title: "Noted", published: false)
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:two)) { [ page, block ].each { |subject| Notes::Start.call(subject, body: "A note") } }

    assert ContentBlocks::Destroy.call(block).ok?

    assert_equal [ page ], Notes::Thread.all.map(&:subject)
  end

  # The order (`docs/reference/notes.md`, "Removal"): the page's row lock,
  # which every notes service takes first too; then the block; then its
  # notes, removed by a `Notes::Remove` that asks the page's edit right of a
  # page that is still there. Statement order only.
  test "a block's notes are removed after the block is deleted, under the page's lock" do
    page = create_page(title: "Noted", published: false)
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:two)) { Notes::Start.call(block, body: "A note") }

    statements = capture_sql { assert ContentBlocks::Destroy.call(block).ok? }

    lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
    deleted = statements.index { |sql| sql.start_with?('DELETE FROM "content_blocks"') }
    first_note = statements.index { |sql| sql.include?('"note_threads"') }
    assert_operator lock, :<, deleted
    assert_operator deleted, :<, first_note
    assert_equal 1, statements.count { |sql| sql.start_with?('DELETE FROM "note_threads"') }
  end

  test "deleting a section with its blocks deletes the notes of each" do
    page, section, = noted_section

    assert ContentBlocks::Destroy.call(section).ok?

    assert_equal [ page ], Notes::Thread.all.map(&:subject)
  end

  test "removing a section and keeping its blocks keeps their notes" do
    page, section, inside = noted_section

    assert ContentBlocks::Destroy.call(section, keep_blocks: true).ok?

    assert_equal [ page, inside ].map(&:id).sort, Notes::Thread.pluck(:subject_id).sort
  end

  test "a block moved into a section keeps its threads under the page" do
    page = create_page(title: "Noted", published: false)
    section = page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    block = page.content_blocks.create!(block_type: "rich_text", position: 1)
    thread = as(users(:two)) { Notes::Start.call(block, body: "A note") }.record

    assert ContentBlocks::Reorder.call(page, [ block.id ], section: section.id, column: 1, moved_from: { block.id => { section_id: "", column: "" } }).ok?

    assert_equal [ block, page ], [ thread.reload.subject, thread.container ]
    assert_equal section.id, block.reload.section_id
  end
end
