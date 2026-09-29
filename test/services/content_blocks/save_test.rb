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
end
