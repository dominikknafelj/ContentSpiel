require "test_helper"

class ContentBlocks::DuplicateTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Duplicate", published: false)
    @first = @page.content_blocks.create!(block_type: "rich_text", position: 0, body: rich_doc("Copied text"))
    @section = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "one_two", "background" => "tinted" })
    @last = @page.content_blocks.create!(block_type: "rich_text", position: 2)
    @image = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 2, position: 0, caption: "Kept", media_asset: create_media_asset)
    @text_b = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1, body: rich_doc("Second"))
    @text_a = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 0, body: rich_doc("First"))
    # The image block was made around the service, so its usage row is too.
    Media::UsageIndex.refresh(@image)
  end

  test "a top-level block's copy stands right after it, with its content" do
    result = ContentBlocks::Duplicate.call(@first, actor: nil)

    assert result.ok?
    assert_equal [ @first, result.record, @section, @last ], @page.content_blocks.top_level.reorder(:position).to_a
    assert_equal @first.body_document(locale: "en").to_h, result.record.body_document(locale: "en").to_h
  end

  test "a block in a column is copied into the same column, right after it" do
    copy = ContentBlocks::Duplicate.call(@text_a, actor: nil).record

    assert_equal [ @text_a, copy, @text_b ], @page.content_blocks.in_column(@section, 1).reorder(:position).to_a
  end

  test "a section is copied with every block in it, column by column, after the section" do
    result = nil
    assert_difference -> { ContentBlock.count }, 4 do
      result = ContentBlocks::Duplicate.call(@section, actor: nil)
    end
    copy = result.record

    assert_equal [ @first, @section, copy, @last ], @page.content_blocks.top_level.reorder(:position).to_a
    assert_equal({ "layout" => "one_two", "background" => "tinted", "width" => "content" }, copy.settings)
    inside = copy.section_blocks.to_a
    assert_equal [ [ "rich_text", 1, 0 ], [ "rich_text", 1, 1 ], [ "image", 2, 0 ] ], inside.map { |block| [ block.block_type, block.section_column, block.position ] }
    assert_equal [ "First", "Second" ], inside.first(2).map { |block| block.body_document(locale: "en").plain_paragraphs.first }
    assert_equal [ @image.media_asset_id, "Kept" ], [ inside.last.media_asset_id, inside.last.caption ]
    assert_equal 2, Media::Usage.where(media_asset_id: @image.media_asset_id, role: "block_image").count
    assert_equal 3, @section.section_blocks.reload.size
  end

  test "a copy refused part-way leaves nothing behind" do
    # May edit this draft page, may not choose images: the image block's copy is refused.
    result = as(page_editor_without_media) { ContentBlocks::Duplicate.call(@section) }

    assert_predicate result, :denied?
    assert_equal 6, @page.content_blocks.reload.size
  end

  test "a refused copy of an image is one access.denied for media.upload, which survives the copy's rollback" do
    assert_difference -> { Audit::Event.where(action: "access.denied").count }, 1 do
      assert_predicate as(page_editor_without_media) { ContentBlocks::Duplicate.call(@image) }, :denied?
    end
    event = Audit::Event.where(action: "access.denied").last
    assert_equal [ "media.upload", @image.id ], [ event.metadata["permission"], event.subject_id ]
  end

  test "an actor who may not edit the page copies nothing" do
    nobody = User.create!(email_address: "nobody-duplicate@example.com", password: "a long enough password")

    assert_no_difference -> { ContentBlock.count } do
      assert_predicate as(nobody) { ContentBlocks::Duplicate.call(@first) }, :denied?
    end
  end

  # A copy that fails after others were made: the image in column 2 went to
  # the trash, so its copy is refused when the two texts of column 1 and the
  # section itself have been written. None of them stays.
  test "a section whose last block can't be copied is not copied at all, and nothing is recorded" do
    @image.media_asset.update_columns(trashed_at: Time.current)

    result = nil
    assert_no_difference [ -> { ContentBlock.count }, -> { Audit::Event.count }, -> { Media::Usage.count } ] do
      result = ContentBlocks::Duplicate.call(@section, actor: nil)
    end

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "Image doesn't exist" ], result.errors
    assert_equal [ @first, @section, @last ], @page.content_blocks.top_level.reorder(:position).to_a
  end

  test "a duplicate is block.created for each copy and one block.reordered on the page" do
    assert_difference -> { Audit::Event.where(action: "block.created").count }, 4 do
      assert_difference -> { Audit::Event.where(action: "block.reordered").count }, 1 do
        ContentBlocks::Duplicate.call(@section, actor: nil)
      end
    end
    event = Audit::Event.where(action: "block.reordered").last
    assert_equal [ "Page", @page.id ], [ event.subject_type, event.subject_id ]

    assert_difference -> { Audit::Event.where(action: "block.reordered").count }, 1 do
      ContentBlocks::Duplicate.call(@text_a, actor: nil)
    end
    assert_equal({ "section_id" => @section.id, "column" => 1 }, Audit::Event.where(action: "block.reordered").last.metadata)
  end

  test "every locale's text is copied, and the copy is its own block" do
    with_locales(%w[en de], default: "en") do
      ContentBlocks::Save.call(@image, translations: { "de" => { caption: "Behalten" } }, actor: nil)
      copy = ContentBlocks::Duplicate.call(@image.reload, actor: nil).record

      assert_equal [ "Kept", "Behalten" ], %w[en de].map { |code| Mobility.with_locale(code) { copy.caption } }
      assert_not_equal @image.id, copy.id
      assert_equal [ @section.id, 2, 1 ], [ copy.section_id, copy.section_column, copy.position ]
    end
  end

  # A source another tab deleted, moved or emptied since this request loaded
  # it is read again under the page's lock.
  test "a source deleted meanwhile is a failure with a message, and one moved meanwhile is copied where it is now" do
    stale = ContentBlock.find(@first.id)
    assert ContentBlocks::Destroy.call(@first, actor: nil).ok?

    gone = nil
    assert_no_difference -> { ContentBlock.count } do
      gone = ContentBlocks::Duplicate.call(stale, actor: nil)
    end
    assert_equal [ ContentBlocks::Duplicate::GONE ], gone.errors

    stale = ContentBlock.find(@last.id)
    assert ContentBlocks::Reorder.call(@page, [ @image.id, @last.id ], section: @section.id, column: 2, moved_from: { @last.id => { section_id: nil, column: nil } }, actor: nil).ok?
    copy = ContentBlocks::Duplicate.call(stale, actor: nil).record

    assert_equal [ @image, @last, copy ], @page.content_blocks.in_column(@section, 2).reorder(:position).to_a
  end

  # The same order of locks as every other write to a page's blocks: the
  # page's row first, then block rows -- before the saves and the reorder a
  # duplicate runs, which each ask for it again and get it at once.
  test "a duplicate locks the page's row before it reads or writes a block, at the top level and in a section" do
    [ @first, @text_a, @section ].each do |source|
      statements = capture_sql { assert ContentBlocks::Duplicate.call(source, actor: nil).ok? }
      lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
      block = statements.index { |sql| sql.include?('"content_blocks"') }

      assert_operator lock, :<, block
    end
  end

  private

  # May edit this draft page, may not choose images.
  def page_editor_without_media
    @page_editor_without_media ||= begin
      user = User.create!(email_address: "no-media@example.com", password: "a long enough password")
      group = AccessControl::Group.create!(name: "Page editors without media")
      %w[pages.read pages.edit].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: {}) }
      AccessControl::Membership.create!(group: group, user: user)
      user
    end
  end
end
