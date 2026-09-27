require "test_helper"

class Admin::ContentBlocksTest < ActionDispatch::IntegrationTest
  # `perform_enqueued_jobs` (fix round 1's duplicate-blob test): a
  # `has_one_attached` detach/destroy purges its blob via `:purge_later`, an
  # `ActiveJob` -- the test queue adapter never runs one on its own, so
  # without this helper `source.destroy` below would leave the (buggy,
  # shared) blob un-purged and the very bug this test exists to catch would
  # pass by accident.
  include ActiveJob::TestHelper

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

  test "updating a deleted block answers gone" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    block.destroy!
    patch "#{blocks_path}/#{block.id}", params: { block: { body: "<p>x</p>" } }, as: :turbo_stream
    assert_response :gone
    assert_includes response.body, "This block was deleted"
  end

  test "an unavailable block type renders a card with delete only" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    block.update_column(:block_type, "gone/thing")
    get "/cs-studio/pages/#{@page.id}"
    assert_includes response.body, "Unavailable type — gone/thing"
  end

  # Fix round 1 (critical): the original `duplicate` re-attached the
  # source's own blob (`copy.image.attach(source.image.blob)`), so both
  # blocks pointed at one `ActiveStorage::Blob` row -- destroying *either*
  # block purges that shared blob (`has_one_attached`'s default `dependent:
  # :purge_later`) out from under the other one.
  test "duplicating an image block gives the copy its own independent blob" do
    source = image_block_with_image

    post "#{blocks_path}/#{source.id}/duplicate", as: :turbo_stream
    assert_response :success

    copy = @page.content_blocks.order(:position).last
    assert_not_equal source.id, copy.id
    assert copy.image.attached?
    assert_not_equal source.image.blob_id, copy.image.blob_id, "the copy must not share the source's blob"

    perform_enqueued_jobs { source.destroy! }

    assert copy.reload.image.attached?
    assert_equal "tiny.png", copy.image.filename.to_s
    assert copy.image.blob.download.present?, "the copy's own blob must still be downloadable"
  end

  # Fix round 2 (this task's own label bug, spotted alongside round 1's
  # review): the shared `admin/shared/_hero_image_field` partial used to
  # hard-code `name: "hero_image"`, so a block's own image column's label
  # always read "Hero image" -- unrelated to the field it actually is.
  test "a block's own image column labels itself Image, not Hero image" do
    block = image_block_with_image
    get "/cs-studio/pages/#{@page.id}"

    assert_select "label", text: "Image"
    assert_select "label", text: "Hero image", count: 0
  end

  # The next four mirror `Admin::PageEditorTest`'s own hero-image cases
  # (Task 4 fix rounds 1/2) for a block's own `image` column -- same bugs,
  # same fixes, same shared code path (`Admin::FileParams
  # #drop_blank_file_params`, the "Remove image" checkbox, the shared
  # partial), just reached through the block card's own autosave endpoint
  # instead of the page settings form's.
  test "autosaving another field doesn't clear an already-attached block image" do
    block = image_block_with_image

    patch "#{blocks_path}/#{block.id}",
      params: { block: { caption: "A caption", image: "" }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    block.reload
    assert_equal "A caption", block.caption(locale: :en)
    assert block.image.attached?
  end

  test "the explicit remove-image checkbox detaches a block's image" do
    block = image_block_with_image

    patch "#{blocks_path}/#{block.id}",
      params: { block: { remove_image: "1" }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    assert_not block.reload.image.attached?
  end

  test "a new upload wins over a stale remove flag in the same save" do
    block = image_block_with_image

    patch "#{blocks_path}/#{block.id}",
      params: {
        block: { image: fixture_file_upload("tiny.png", "image/png"), remove_image: "1" },
        base_updated_at: block.updated_at.iso8601(6)
      }, as: :turbo_stream
    assert_response :success

    assert block.reload.image.attached?
  end

  test "the success stream after an image change re-renders the image section without a checked remove box" do
    block = image_block_with_image

    patch "#{blocks_path}/#{block.id}",
      params: { block: { remove_image: "1" }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success

    assert_includes response.body, "#{Admin::BlockCardComponent.error_prefix(block)}-image-section"
    assert_not_includes response.body, "block[remove_image]"
  end

  private

  def image_block_with_image
    block = @page.content_blocks.create!(block_type: "image", position: 0)
    block.image.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    assert block.image.attached?
    block
  end
end
