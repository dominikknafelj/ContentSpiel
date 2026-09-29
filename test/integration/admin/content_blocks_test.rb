require "test_helper"

class Admin::ContentBlocksTest < ActionDispatch::IntegrationTest
  # `perform_enqueued_jobs` (fix round 1's duplicate-blob test): a
  # `has_one_attached` detach/destroy purges its blob via `:purge_later`, an
  # `ActiveJob` -- the test queue adapter never runs one on its own, so
  # without this helper `source.destroy` below would leave the (buggy,
  # shared) blob un-purged and the very bug this test exists to catch would
  # pass by accident.
  include ActiveJob::TestHelper
  include TestTypes

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    @page = create_page(title: "About")
  end

  def blocks_path = "/cs-studio/pages/#{@page.id}/content_blocks"

  test "adding a block streams its card in" do
    post blocks_path, params: { block: { block_type: "post_list" } }, as: :turbo_stream
    assert_response :success
    block = @page.content_blocks.last
    assert_equal "post_list", block.block_type
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(block)
  end

  test "typed settings autosave with per-field errors" do
    block = @page.content_blocks.create!(block_type: "post_list", position: 0)
    patch "#{blocks_path}/#{block.id}", params: { block: { settings: { limit: "0" } }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_includes response.body, "must be greater than or equal to 1"

    patch "#{blocks_path}/#{block.id}", params: { block: { settings: { limit: "3" } }, base_updated_at: block.reload.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_equal 3, block.reload.settings_object.limit
  end

  # Fix (final-fixes round, finding 10): the end-of-list picker (rendered
  # once, statically, below the whole list) and a card's own trailing
  # between-picker (`last: false` only) used to both end up showing at the
  # tail after an append -- the newly-appended card kept the default
  # `last: false` regardless of actually being last now, so it rendered its
  # own redundant trailing picker right above the page's already-present
  # end-of-list one -- and the card that *was* last lost nothing (it never
  # had one to lose), but was left permanently missing the between-picker
  # it should have gained the moment something followed it.
  test "adding a block at the end gives the new card no trailing picker, and gives the previous last card one" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)

    post blocks_path, params: { block: { block_type: "rich_text" } }, as: :turbo_stream
    assert_response :success

    new_block = @page.content_blocks.order(:position).last
    assert_not_includes response.body, "block-picker-after-#{new_block.id}"
    assert_includes response.body, "block-picker-after-#{first.id}"
    assert_includes response.body, %(<turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(first)}">)
  end

  test "adding a block between two existing cards touches neither one's own picker" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "rich_text", position: 1)

    post blocks_path, params: { block: { block_type: "rich_text" }, after_id: first.id }, as: :turbo_stream
    assert_response :success

    assert_not_includes response.body, %(<turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(first)}">)
    assert_not_includes response.body, %(<turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(second)}">)
  end

  test "duplicating the last block gives the copy no trailing picker, and gives the source one" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)

    post "#{blocks_path}/#{first.id}/duplicate", as: :turbo_stream
    assert_response :success

    copy = @page.content_blocks.order(:position).last
    assert_not_equal first.id, copy.id
    assert_not_includes response.body, "block-picker-after-#{copy.id}"
    assert_includes response.body, "block-picker-after-#{first.id}"
  end

  test "duplicating a block that isn't last doesn't touch the actual last card's picker" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "rich_text", position: 1)

    post "#{blocks_path}/#{first.id}/duplicate", as: :turbo_stream
    assert_response :success

    assert_not_includes response.body, %(<turbo-stream action="replace" target="#{ActionView::RecordIdentifier.dom_id(second)}">)
  end

  test "reorder, duplicate and delete" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    patch "#{blocks_path}/reorder", params: { ids: [ second.id, first.id ] }, as: :turbo_stream
    assert_equal [ second, first ], @page.content_blocks.reload.to_a

    post "#{blocks_path}/#{first.id}/duplicate", as: :turbo_stream
    assert_equal 3, @page.content_blocks.count

    delete "#{blocks_path}/#{first.id}", as: :turbo_stream
    assert_not ContentBlock.exists?(first.id)
  end

  # Fix round 1 (Task 7 review): regression test for the `Admin::Columns::
  # RichTextColumnComponent` fix (`name` -> `html_name`) -- the body has to
  # arrive nested as `block[body]` or `split_block_params`'s own
  # `block_params.key?(:body)` check never sees it. Since the JSON-document
  # switch the param is the hidden input's document JSON String.
  test "a rich_text block's body autosaves" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    patch "#{blocks_path}/#{block.id}", params: { block: { body: rich_doc("Hello there").to_json }, base_updated_at: block.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :success
    assert_equal rich_doc("Hello there"), block.reload.body_document(locale: "en").to_h
  end

  test "a rich_text block's body saves into the form's locale" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0, body: rich_doc("English"))
    patch "#{blocks_path}/#{block.id}", params: { locale: "de", block: { body: rich_doc("Deutsch").to_json }, base_updated_at: block.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :success
    stored = block.reload.read_attribute(:body)
    assert_equal rich_doc("Deutsch"), stored["de"]
    assert_equal rich_doc("English"), stored["en"]
  end

  test "an invalid block body answers 422 with the error in the body slot" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    patch "#{blocks_path}/#{block.id}", params: { block: { body: "{broken" }, base_updated_at: block.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :unprocessable_entity
    assert_select_in_stream "block-#{block.id}-body-errors", /Body/
  end

  # Fix (final-fixes round, finding 2): the block-card counterpart to
  # `Admin::PostsTest`'s own "removing every speaker" case -- no built-in
  # block type declares a `groups` field, so `test/quote` (`test/support/
  # test_types.rb`) is the one fixture that exercises this for a block's own
  # settings at all.
  test "removing every row of a block's own groups field saves it as empty" do
    with_test_types do
      block = @page.content_blocks.create!(block_type: "test/quote", position: 0,
        settings: { "speakers" => [ { "name" => "Ada" } ] }, translated_settings: { "en" => { "text" => "Hello" } })
      assert_equal %w[Ada], block.settings_object.group(:speakers).map(&:name)

      patch "#{blocks_path}/#{block.id}",
        params: { block: { groups_present: [ "speakers" ] }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
      assert_response :success
      assert_equal [], block.reload.settings_object.group(:speakers).map(&:name)
    end
  end

  test "updating a deleted block answers gone" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    block.destroy!
    patch "#{blocks_path}/#{block.id}", params: { block: { body: rich_doc("x").to_json } }, as: :turbo_stream
    assert_response :gone
    assert_includes response.body, "This block was deleted"
  end

  test "an unavailable block type renders a card with delete only" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    block.update_column(:block_type, "gone/thing")
    get "/cs-studio/pages/#{@page.id}"
    assert_includes response.body, "Unavailable type — gone/thing"
  end

  # Media library Task 4: an image block's image is a library asset, so a
  # duplicate points at the same asset -- nothing is copied, and the asset
  # can't be deleted while either block uses it (the FK restricts), which
  # is what the old "independent blob" copy (fix round 1) was protecting.
  test "duplicating an image block shares the library asset" do
    source = image_block_with_image

    assert_no_difference "Media::Asset.count" do
      post "#{blocks_path}/#{source.id}/duplicate", as: :turbo_stream
    end
    assert_response :success

    copy = @page.content_blocks.order(:position).last
    assert_not_equal source.id, copy.id
    assert_equal source.media_asset, copy.media_asset

    source.destroy!
    assert copy.reload.media_asset.file.attached?
  end

  # Final fix wave (Minor 6): the copy's image is set inside
  # `ContentBlocks::Save`, so the `block.created` event's snapshot has it --
  # as `media_asset_id` since media library Task 4.
  test "duplicating an image block records block.created with the image in its snapshot" do
    source = image_block_with_image

    post "#{blocks_path}/#{source.id}/duplicate", as: :turbo_stream
    assert_response :success

    copy = @page.content_blocks.order(:position).last
    event = Audit::Event.find_by!(action: "block.created", subject: copy)
    assert_equal source.media_asset_id, event.snapshot["media_asset_id"]
    assert_not event.snapshot.key?("image")
  end

  # Duplicating copies every locale's JSON body document verbatim (the
  # ActionText-era version of this test guarded against a re-rendered
  # `trix-content` wrapper nesting itself on every duplicate; a JSON
  # document is copied as data, so the same guarantee is "byte-for-byte
  # equal, even duplicated twice").
  test "duplicating a rich_text block copies every locale's body document, even duplicated twice" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0, body: rich_doc("Hi **there**"))
    block.assign_body(rich_doc("Hallo"), locale: "de")
    block.save!
    original = block.reload.read_attribute(:body)

    post "#{blocks_path}/#{block.id}/duplicate", as: :turbo_stream
    assert_response :success
    copy = @page.content_blocks.order(:position).last
    assert_equal original, copy.read_attribute(:body)

    post "#{blocks_path}/#{copy.id}/duplicate", as: :turbo_stream
    assert_response :success
    copy2 = @page.content_blocks.order(:position).last
    assert_equal original, copy2.read_attribute(:body)
  end

  # The image column is a library image field (media library Task 8):
  # labelled "Image" (never the page's "Hero image"), a hidden
  # `media_asset_id` the card's autosave sends, and the image's own default
  # alt/caption as the per-use overrides' placeholders.
  test "an image block's card shows the picker field and the image's defaults as the overrides' placeholders" do
    block = image_block_with_image
    block.media_asset.update!(alt: "A dog", caption: "Our dog")
    prefix = Admin::BlockCardComponent.error_prefix(block)

    get "/cs-studio/pages/#{@page.id}"
    assert_response :success

    assert_select "##{prefix}-image-section[data-controller='admin--media-field']" do
      assert_select "p", text: "Image"
      assert_select "input[type=hidden][name='block[media_asset_id]'][value='#{block.media_asset_id}']"
      assert_select "button", text: "Change image"
    end
    assert_select "p", text: "Hero image", count: 0
    assert_select "input[name='block[alt]'][placeholder='A dog']"
    assert_select "input[name='block[caption]'][placeholder='Our dog']"
    assert_equal({ "alt" => "#{prefix}-alt", "caption" => "#{prefix}-caption" },
      JSON.parse(css_select("##{prefix}-image-section").first["data-admin--media-field-placeholder-ids-value"]))
  end

  # Every autosave resends the hidden input's stored id -- a no-op.
  test "autosaving another field resends the stored image id and keeps the image" do
    block = image_block_with_image
    asset = block.media_asset

    patch "#{blocks_path}/#{block.id}",
      params: { block: { caption: "A caption", media_asset_id: asset.id.to_s }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    block.reload
    assert_equal "A caption", block.caption(locale: :en)
    assert_equal asset, block.media_asset
  end

  test "choosing a library image sets the block's image" do
    block = image_block_with_image
    chosen = create_media_asset(filename: "medium.png")

    assert_no_difference "Media::Asset.count" do
      patch "#{blocks_path}/#{block.id}",
        params: { block: { media_asset_id: chosen.id.to_s }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    end
    assert_response :success

    assert_equal chosen, block.reload.media_asset
    assert Media::Usage.exists?(media_asset: chosen, owner: block, role: "block_image")
  end

  test "an empty image id (Remove) clears a block's image" do
    block = image_block_with_image

    patch "#{blocks_path}/#{block.id}",
      params: { block: { media_asset_id: "" }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    assert_nil block.reload.media_asset
  end

  test "an image id naming no asset is refused into the image column's error slot" do
    block = image_block_with_image
    previous = block.media_asset

    patch "#{blocks_path}/#{block.id}",
      params: { block: { media_asset_id: (Media::Asset.maximum(:id) + 1).to_s }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity

    assert_includes response.body, %(target="#{Admin::BlockCardComponent.error_prefix(block)}-image-errors")
    assert_includes response.body, "Image doesn&#39;t exist"
    assert_equal previous, block.reload.media_asset
  end

  # Only a type that `uses :image` takes an image id at all.
  test "a media_asset_id sent to a block type without an image is ignored" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)

    patch "#{blocks_path}/#{block.id}",
      params: { block: { media_asset_id: create_media_asset.id.to_s }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    assert_nil block.reload.media_asset_id
  end

  # The interim upload field (media library Task 4) is gone.
  test "an image file param is ignored and uploads nothing" do
    block = image_block_with_image
    previous = block.media_asset

    assert_no_difference "Media::Asset.count" do
      patch "#{blocks_path}/#{block.id}",
        params: { block: { image: fixture_file_upload("medium.png", "image/png") }, base_updated_at: block.updated_at.iso8601(6) },
        as: :turbo_stream
    end
    assert_response :success
    assert_equal previous, block.reload.media_asset
  end

  private

  def image_block_with_image
    @page.content_blocks.create!(block_type: "image", position: 0, media_asset: create_media_asset)
  end
end
