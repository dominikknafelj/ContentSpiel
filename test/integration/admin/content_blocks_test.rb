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
