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

  test "a reorder answers with an Undo toast that restores the previous order and the list" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    third = @page.content_blocks.create!(block_type: "rich_text", position: 2)

    patch "#{blocks_path}/reorder", params: { ids: [ third.id, first.id, second.id ] }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action='append'][target='toasts'] .admin-toast[data-kind='undo']", text: /order changed/i
    undo = css_select("turbo-stream[target='toasts'] form").first
    assert_equal "patch", css_select(undo, "input[name='_method']").first["value"]
    query = Rack::Utils.parse_nested_query(URI.parse(undo["action"]).query)
    assert_equal [ first.id, second.id, third.id ].map(&:to_s), query["ids"]
    assert_equal "1", query["undo"]

    # The Undo goes through the same service and answers by re-rendering the
    # list in the restored order (the client's DOM is still the dropped one).
    patch undo["action"], as: :turbo_stream
    assert_response :success
    assert_equal [ first, second, third ], @page.content_blocks.reload.to_a
    assert_select "turbo-stream[action='update'][target='content-blocks-list']"
    ids = Nokogiri::HTML5.fragment(response.body).css("turbo-stream[target='content-blocks-list'] [data-block-id]").map { |card| card["data-block-id"] }
    assert_equal [ first.id, second.id, third.id ].map(&:to_s), ids
    assert_select "turbo-stream[target='toasts'] .admin-toast form", count: 0
  end

  test "a reorder that changes nothing offers no Undo" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    second = @page.content_blocks.create!(block_type: "rich_text", position: 1)
    patch "#{blocks_path}/reorder", params: { ids: [ first.id, second.id ] }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[target='toasts']", count: 0
  end

  test "a refused reorder offers no Undo" do
    first = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    patch "#{blocks_path}/reorder", params: { ids: [ first.id, 0 ] }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_select "turbo-stream[target='toasts']", count: 0
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

    # Fix round 1 (I2): the field comes back with the stored image and the
    # message inside it.
    section = response.body.index(%(target="#{Admin::BlockCardComponent.error_prefix(block)}-image-section"))
    assert section, "expected a stream replacing the image field"
    field = response.body[section..]
    assert_includes field, %(name="block[media_asset_id]" id="#{Admin::BlockCardComponent.error_prefix(block)}-image" value="#{previous.id}")
    assert_includes field, "Image doesn&#39;t exist"
  end

  # Review Focus 5 for a block: choosing needs `media.upload` on top of the
  # page's edit right.
  test "choosing a block image without media.upload is a 403 and changes nothing" do
    block = image_block_with_image
    stored = block.media_asset
    chosen = create_media_asset(filename: "medium.png")
    group = access_control_groups(:branch_editors)
    %w[pages.read pages.edit pages.publish].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: {}) }
    sign_in_as(users(:editor_branch))

    patch "#{blocks_path}/#{block.id}",
      params: { block: { media_asset_id: chosen.id.to_s }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :forbidden

    assert_equal stored, block.reload.media_asset
    assert_equal "media.upload", Audit::Event.where(action: "access.denied").last.metadata["permission"]
    assert_includes response.body, %(target="#{Admin::BlockCardComponent.error_prefix(block)}-image-section")
  end

  # Final fix wave (T6), pinning the Task 6 ruling: a duplicate chooses its
  # image again (through `ContentBlocks::Save`), so copying an image block
  # needs `media.upload` too -- the page's edit right alone is refused, and
  # no copy is made.
  test "duplicating an image block needs media.upload" do
    source = image_block_with_image
    group = access_control_groups(:branch_editors)
    %w[pages.read pages.edit pages.publish].each { |key| AccessControl::Grant.create!(group: group, permission: key, scope: {}) }
    sign_in_as(users(:editor_branch))

    assert_no_difference -> { @page.content_blocks.count } do
      post "#{blocks_path}/#{source.id}/duplicate", as: :turbo_stream
    end
    assert_response :forbidden
    assert_equal "media.upload", Audit::Event.where(action: "access.denied").last.metadata["permission"]
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
  # Final fix wave I3: a block write touches its page, so a block response
  # also hands the page settings form on the same screen the page's fresh
  # `updated_at` -- but only when the base that form holds (sent along as
  # `X-Page-Base-Updated-At`) was still current before this write;
  # otherwise its next autosave would report "Changed elsewhere" against
  # nothing but this same editor.
  test "block writes refresh the page form's base so its next save isn't stale" do
    block = @page.content_blocks.create!(block_type: :rich_text, position: 0)
    travel 1.minute

    patch "#{blocks_path}/#{block.id}", params: { block: { body: rich_doc("Edited").to_json }, base_updated_at: block.updated_at.iso8601(6) },
      headers: page_base_header(@page.reload.updated_at), as: :turbo_stream
    assert_response :success
    fresh = @page.reload.updated_at.iso8601(6)
    assert_equal fresh, streamed_page_base

    patch "/cs-studio/pages/#{@page.id}", params: { page: { title: "About us" }, base_updated_at: fresh }, as: :turbo_stream
    assert_response :success
    assert_no_match(/Changed elsewhere/, response.body)

    travel 1.minute
    patch "#{blocks_path}/reorder", params: { ids: [ block.id ] }, headers: page_base_header(@page.reload.updated_at), as: :turbo_stream
    assert_response :success
    delete "#{blocks_path}/#{block.id}", headers: page_base_header(@page.reload.updated_at), as: :turbo_stream
    assert_response :success
    assert_equal @page.reload.updated_at.iso8601(6), streamed_page_base
  end

  test "a block save made on a stale base is refused, names who changed it, and keeps the newer text" do
    block = @page.content_blocks.create!(block_type: :image, position: 0)
    stale = block.updated_at.iso8601(6)
    travel 1.minute
    as(users(:two), channel: :admin) { ContentBlocks::Save.call(block, translations: { "en" => { caption: "Changed by someone else" } }) }

    patch "#{blocks_path}/#{block.id}", params: { block: { caption: "My stale edit" }, base_updated_at: stale }, as: :turbo_stream
    assert_response :conflict
    assert_equal "Changed by someone else", block.reload.caption
    assert_select_in_stream "block-#{block.id}-save-status", /CHANGED ELSEWHERE/
    assert_select_in_stream "editor-notice", /Changed by .+Reload/m
    assert_no_match(/block-#{block.id}-base-updated-at/, response.body)
    assert_no_match(/page-base-updated-at/, response.body, "a refused save vouches for nothing")
  end

  test "a block save on a current base still saves" do
    block = @page.content_blocks.create!(block_type: :image, position: 0)
    patch "#{blocks_path}/#{block.id}", params: { block: { caption: "Fresh" }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_equal "Fresh", block.reload.caption
  end

  test "a block on a live page saves 'to site', like the page does; on a draft page it just saves" do
    block = @page.content_blocks.create!(block_type: :image, position: 0)
    assert @page.live?
    patch "#{blocks_path}/#{block.id}", params: { block: { caption: "Live" }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_select_in_stream "block-#{block.id}-save-status", /● SAVED TO SITE \d\d:\d\d/

    draft = create_page(title: "Draft page", published: false)
    draft_block = draft.content_blocks.create!(block_type: :image, position: 0)
    patch "/cs-studio/pages/#{draft.id}/content_blocks/#{draft_block.id}", params: { block: { caption: "Draft" }, base_updated_at: draft_block.updated_at.iso8601(6) }, as: :turbo_stream
    assert_select_in_stream "block-#{draft_block.id}-save-status", /\ASAVED \d\d:\d\d/
  end

  # Fix round 2: the refresh above must never paper over a real conflict.
  # A loaded the editor, B then saved the page's settings, then A edited a
  # block: A's page form still holds the pre-B base, so the block response
  # must leave it alone -- A's next page autosave is then reported as
  # "Changed elsewhere", as it would have been without the block edit.
  test "a block edit doesn't hide a page save made elsewhere in the meantime" do
    block = @page.content_blocks.create!(block_type: :rich_text, position: 0)
    a_base = @page.reload.updated_at
    travel 1.minute
    assert Current.set(actor: users(:two), channel: :admin) { Pages::Save.call(@page.reload, translations: { Locales.default => { title: "B's title" } }) }.ok?
    travel 1.minute

    patch "#{blocks_path}/#{block.id}", params: { block: { body: rich_doc("A's edit").to_json }, base_updated_at: block.reload.updated_at.iso8601(6) },
      headers: page_base_header(a_base), as: :turbo_stream
    assert_response :success
    assert_nil Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='page-base-updated-at']")

    patch "/cs-studio/pages/#{@page.id}", params: { page: { subtitle: "A's subtitle" }, base_updated_at: a_base.iso8601(6) }, as: :turbo_stream
    assert_response :conflict
    assert_match(/CHANGED ELSEWHERE/, response.body)
    assert_select_in_stream "editor-notice", /Changed by two@example\.com/
    assert_nil @page.reload.subtitle
    assert_equal "B's title", @page.title
  end

  # No page base sent (a client that doesn't send one): nothing to vouch
  # for, so the page form's base is never moved.
  test "a block write without the page form's base doesn't stream one" do
    block = @page.content_blocks.create!(block_type: :rich_text, position: 0)

    patch "#{blocks_path}/#{block.id}", params: { block: { body: rich_doc("Edited").to_json }, base_updated_at: block.updated_at.iso8601(6) },
      as: :turbo_stream
    assert_response :success
    assert_nil Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='page-base-updated-at']")
  end

  def page_base_header(time) = { "X-Page-Base-Updated-At" => time.iso8601(6) }

  def streamed_page_base
    stream = Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[target='page-base-updated-at']")
    assert stream, "expected the page form's base in:\n#{response.body}"
    stream.inner_html[/value="([^"]+)"/, 1]
  end

  # Task 7: a translation tab's block form no longer renders the untranslated
  # settings as inputs (they are read-only under "Shared fields"), so its
  # autosave sends exactly the keys below -- and the shared values must be
  # exactly what they were.
  test "a translation-tab save of a block leaves its shared settings untouched" do
    with_test_types do
      block = ContentBlocks::Save.call(@page.content_blocks.new, attributes: { block_type: "test/quote", settings: { cite: "https://example.com/a" } },
        translations: { "en" => { settings: { text: "To be" } } }).record
      assert block.persisted?

      get "/cs-studio/pages/#{@page.id}", params: { locale: "de" }
      assert_select "form.admin-translation-form input[name='block[settings][text]']"
      assert_select "form.admin-translation-form input[name='block[settings][cite]']", count: 0

      patch "/cs-studio/pages/#{@page.id}/content_blocks/#{block.id}",
        params: { locale: "de", block: { settings: { text: "Sein" } }, base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream

      assert_response :success
      block.reload
      assert_equal "https://example.com/a", block.settings["cite"]
      assert_equal "Sein", block.settings_object(locale: :de).text
      assert_equal "To be", block.settings_object(locale: Locales.default).text
    end
  end

  test "a translation-tab save of a post_list block (a form with no inputs but the base) leaves its settings untouched" do
    block = ContentBlocks::Save.call(@page.content_blocks.new, attributes: { block_type: "post_list", settings: { content_type: "blog", limit: 3 } }).record

    patch "/cs-studio/pages/#{@page.id}/content_blocks/#{block.id}",
      params: { locale: "de", base_updated_at: block.updated_at.iso8601(6) }, as: :turbo_stream

    block.reload
    assert_equal 3, block.settings["limit"]
    assert_equal "blog", block.settings["content_type"]
    assert_not block.translated_settings.key?("de")
  end
end
