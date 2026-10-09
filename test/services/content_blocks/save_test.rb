require "test_helper"

class ContentBlocks::SaveTest < ActiveSupport::TestCase
  test "appends to the end of the page's blocks when position is nil" do
    page = create_page(title: "Page")

    first = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("One") } })
    second = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Two").to_json } })

    assert first.ok?
    assert second.ok?
    assert_equal 0, first.record.position
    assert_equal 1, second.record.position
    assert_equal rich_doc("One"), first.record.reload.body_document(locale: "en").to_h
    assert_equal rich_doc("Two"), second.record.reload.body_document(locale: "en").to_h
  end

  test "a position given on create is kept, not overridden" do
    page = create_page(title: "Page")
    page.content_blocks.create!(block_type: :rich_text, position: 0)

    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text", position: 5 })

    assert result.ok?
    assert_equal 5, result.record.position
  end

  test "a post_list block with an unknown content type fails" do
    page = create_page(title: "Page")

    result = ContentBlocks::Save.call(ContentBlock.new(owner: page),
      attributes: { block_type: "post_list", settings: { "content_type" => "nope" } })

    assert_not result.ok?
    # The error is keyed "settings.content_type" (`ContentBlock
    # #settings_are_valid`), so its full message reads "Settings.content
    # type ..." -- humanized with a space, not the raw field name.
    assert result.errors.any? { |message| message.match?(/content.type/i) }
  end

  # --- An image block's library image (media library design spec §5.1) ---

  def image_block(page = create_page(title: "Page", published: false))
    as_owner { ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "image" }).record }
  end

  def block_usages(block) = Media::Usage.where(owner: block, role: "block_image").pluck(:media_asset_id)

  test "a media_asset_id sets the block's image and indexes its usage" do
    asset = create_media_asset
    block = image_block

    result = as_owner { ContentBlocks::Save.call(block, attributes: { media_asset_id: asset.id }) }

    assert result.ok?, result.errors.inspect
    assert_equal asset, block.reload.media_asset
    assert_equal [ asset.id ], block_usages(block)
    assert_equal asset.id, Audit::Event.where(action: "block.updated").last.snapshot["media_asset_id"]
  end

  test "an unknown media_asset_id fails validation" do
    block = image_block

    result = as_owner { ContentBlocks::Save.call(block, attributes: { media_asset_id: 0 }, translations: { "en" => { caption: "Changed" } }) }

    assert_not result.ok?
    assert_equal [ "Image doesn't exist" ], result.errors
    assert_nil block.reload.media_asset_id
    assert_nil block.caption
  end

  # Final fix wave (M1): the choose/delete race (see the same test in
  # `Pages::SaveTest`).
  test "an image deleted between the check and the save fails validation" do
    asset = create_media_asset
    block = image_block
    # The check is `Media::Asset.kept.exists?` (trashed images read as
    # missing), so the race is staged on what `.kept` returns.
    racing = Object.new
    racing.define_singleton_method(:exists?) { |*| Media::Asset.where(id: asset.id).delete_all.positive? }

    result = with_singleton_override(Media::Asset, :kept, ->(*) { racing }) do
      as_owner { ContentBlocks::Save.call(block, attributes: { media_asset_id: asset.id }, translations: { "en" => { caption: "Changed" } }) }
    end

    assert_not result.ok?
    assert_equal [ "Image doesn't exist" ], result.errors
    assert_nil block.reload.media_asset_id
    assert_nil block.caption
  end

  # Final fix wave (M1): the rich-text side of the race -- the body's image
  # passes validation and `UsageIndex`'s existence check, then goes before
  # the usage row is written (the FK on `media_usages`).
  test "a body image deleted before its usage row is written fails validation" do
    asset = create_media_asset
    block = as_owner { ContentBlocks::Save.call(ContentBlock.new(owner: create_page(title: "Page", published: false)), attributes: { block_type: "rich_text" }).record }
    insert_all = Media::Usage.method(:insert_all)
    racing = ->(rows, **options) { Media::Asset.where(id: asset.id).delete_all && insert_all.call(rows, **options) }

    result = with_singleton_override(Media::Usage, :insert_all, racing) do
      as_owner { ContentBlocks::Save.call(block, translations: { "en" => { body: rich_doc("::image{asset=\"#{asset.id}\"}") } }) }
    end

    assert_not result.ok?
    assert_equal [ "Body has an image that doesn't exist" ], result.errors
    assert block.reload.body_document(locale: "en").blank?
  end

  # Telling which FK refused the save is about row existence, not trash
  # state: a block still pointing at a *trashed* image (its row is there,
  # so its FK can't be what failed) must not be blamed for a body image
  # that vanished.
  test "a vanished body image isn't blamed on the block's own trashed image" do
    trashed = create_media_asset
    asset = create_media_asset
    block = as_owner { ContentBlocks::Save.call(ContentBlock.new(owner: create_page(title: "Page", published: false)), attributes: { block_type: "rich_text" }).record }
    block.update_columns(media_asset_id: trashed.id)
    trashed.update_columns(trashed_at: Time.current)
    insert_all = Media::Usage.method(:insert_all)
    racing = ->(rows, **options) { Media::Asset.where(id: asset.id).delete_all && insert_all.call(rows, **options) }

    result = with_singleton_override(Media::Usage, :insert_all, racing) do
      as_owner { ContentBlocks::Save.call(block.reload, translations: { "en" => { body: rich_doc("::image{asset=\"#{asset.id}\"}") } }) }
    end

    assert_not result.ok?
    assert_equal [ "Body has an image that doesn't exist" ], result.errors
  end

  test "an actor without media.upload can't set the image, but can clear it" do
    asset = create_media_asset
    block = image_block
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.edit", scope: {})

    refused = as(users(:editor_branch)) { ContentBlocks::Save.call(block, attributes: { media_asset_id: asset.id }) }
    assert refused.denied?
    assert_equal [ "You don't have permission to upload media" ], refused.errors
    assert_nil block.reload.media_asset_id

    as_owner { ContentBlocks::Save.call(block, attributes: { media_asset_id: asset.id }) }
    cleared = as(users(:editor_branch)) { ContentBlocks::Save.call(block, attributes: { media_asset_id: "" }) }
    assert cleared.ok?, cleared.errors.inspect
    assert_nil block.reload.media_asset_id
    assert_empty block_usages(block)
  end

  test "a rich-text block's body images are indexed per locale, and deleting the block removes them" do
    asset = create_media_asset
    page = create_page(title: "Page")

    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
      translations: { "de" => { body: rich_doc("::image{asset=\"#{asset.id}\"}") } }).record
    assert_equal [ [ asset.id, "de" ] ], Media::Usage.where(owner: block, role: "rich_text").pluck(:media_asset_id, :locale)

    assert ContentBlocks::Destroy.call(block).ok?
    assert_empty Media::Usage.where(owner_type: "ContentBlock", owner_id: block.id)
  end

  def section_on(page, layout: "three")
    ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "section", settings: { "layout" => layout } }, actor: nil).record
  end

  def add_to(section, column, type: "rich_text")
    ContentBlocks::Save.call(ContentBlock.new(owner: section.owner), attributes: { block_type: type, section_id: section.id, section_column: column }, actor: nil)
  end

  test "a new block goes to the end of the column it names" do
    page = create_page(title: "Columns")
    section = section_on(page)
    first = add_to(section, 2).record
    second = add_to(section, 2).record
    other = add_to(section, 1).record

    assert_equal [ [ section.id, 2, 0 ], [ section.id, 2, 1 ], [ section.id, 1, 0 ] ],
      [ first, second, other ].map { |block| [ block.section_id, block.section_column, block.position ] }
    assert_equal page, first.owner
  end

  test "a new top-level block is appended among the top-level blocks" do
    page = create_page(title: "Top")
    section = section_on(page)
    3.times { add_to(section, 1) }
    text = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }, actor: nil).record

    assert_equal [ section, text ], page.content_blocks.top_level.reorder(:position).to_a
    assert_equal 1, text.position
  end

  test "a column the section no longer has is refused and nothing is written" do
    page = create_page(title: "Gone column")
    section = section_on(page, layout: "two")

    assert_no_difference -> { ContentBlock.count } do
      result = add_to(section, 3)
      assert_not result.ok?
      assert_not result.denied?
      assert_includes result.errors.to_sentence, "isn't a column of this section"
    end
  end

  test "a section can't be created inside a section, and an existing block's section can't be changed through a save" do
    page = create_page(title: "Rules")
    section = section_on(page)
    assert_not add_to(section, 1, type: "section").ok?

    text = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }, actor: nil).record
    assert ContentBlocks::Save.call(text, attributes: { section_id: section.id, section_column: 1 }, actor: nil).ok?
    assert_nil text.reload.section_id
  end

  test "a layout with fewer columns moves the removed columns' blocks to the end of the last one, in column order" do
    page = create_page(title: "Fold")
    section = section_on(page, layout: "four")
    keep = add_to(section, 2).record
    third_a = add_to(section, 3).record
    third_b = add_to(section, 3).record
    fourth = add_to(section, 4).record

    result = nil
    assert_difference -> { Audit::Event.where(action: "block.updated").count }, 1 do
      result = ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "two" } }, actor: nil)
    end

    assert result.ok?
    assert_equal [ keep, third_a, third_b, fourth ], page.content_blocks.in_column(section, 2).reorder(:position).to_a
    assert_equal [ 0, 1, 2, 3 ], page.content_blocks.in_column(section, 2).reorder(:position).pluck(:position)
    assert_equal [ third_a.id, third_b.id, fourth.id ], Audit::Event.where(action: "block.updated").last.metadata["folded_block_ids"]
    assert_equal 4, ContentBlock.where(section_id: section.id).count
  end

  test "a layout with as many or more columns moves nothing" do
    page = create_page(title: "Widen")
    section = section_on(page, layout: "two")
    block = add_to(section, 2).record

    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "one_two" } }, actor: nil).ok?
    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "four" } }, actor: nil).ok?
    assert_equal [ 2, 0 ], block.reload.then { |b| [ b.section_column, b.position ] }
  end

  test "a save into a column needs the page's edit right like any block" do
    page = create_page(title: "Rights", published: false)
    section = section_on(page)
    nobody = User.create!(email_address: "nobody-columns@example.com", password: "a long enough password")

    result = as(nobody) { ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text", section_id: section.id, section_column: 1 }) }

    assert_predicate result, :denied?
    assert_empty ContentBlock.where(section_id: section.id)
  end

  # The plan's review focus (decision D14): one tab folds a section to fewer
  # columns while another adds into the last one. Both take the page's row
  # lock first, so the add runs after the fold has committed and is judged
  # against the layout as it then stands: refused with a message, and no
  # block is left in a column the section does not have.
  test "an add into a column that a fold has just removed is refused, and no block is left beyond the layout" do
    page = create_page(title: "Two tabs")
    section = section_on(page, layout: "three")
    there = add_to(section, 3).record

    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "two" } }, actor: nil).ok?
    result = add_to(section, 3)

    assert_not result.ok?
    assert_equal [ "Section column isn't a column of this section" ], result.errors
    assert_equal [ [ there.id, 2 ] ], ContentBlock.where(section_id: section.id).pluck(:id, :section_column)
  end

  # The other half of the same race: the second tab still holds the section
  # as it was loaded before the first tab widened it and a block arrived in
  # the new column. Its save writes the old, narrower layout; the fold is
  # decided from the rows under the lock, not from what that stale object
  # remembers, so the block comes along.
  test "a section saved from a copy loaded before it was widened still folds what arrived since" do
    page = create_page(title: "Stale tab")
    section = section_on(page, layout: "two")
    stale = ContentBlock.find(section.id)
    assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "four" } }, actor: nil).ok?
    arrived = add_to(section, 4).record

    assert ContentBlocks::Save.call(stale, attributes: { settings: { "layout" => "two", "background" => "tinted" } }, actor: nil).ok?

    assert_equal [ 2, 0 ], arrived.reload.then { |b| [ b.section_column, b.position ] }
  end

  test "a structural save locks the page's row before it writes, and a save outside a section takes no such lock" do
    page = create_page(title: "Lock")
    section = section_on(page)
    locks = ->(statements) { statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) } }
    first_write = ->(statements) { statements.index { |sql| sql.match?(/\A(INSERT INTO|UPDATE) "content_blocks"/) } }

    into_column = capture_sql { assert add_to(section, 1).ok? }
    layout = capture_sql { assert ContentBlocks::Save.call(section, attributes: { settings: { "layout" => "two" } }, actor: nil).ok? }
    new_section = capture_sql { section_on(page) }
    outside = capture_sql { assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }, actor: nil).ok? }

    [ into_column, layout, new_section ].each do |statements|
      assert_operator locks.call(statements), :<, first_write.call(statements)
    end
    assert_nil locks.call(outside)
  end
end
