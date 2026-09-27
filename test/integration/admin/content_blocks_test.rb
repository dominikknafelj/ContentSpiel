require "test_helper"

class Admin::ContentBlocksTest < ActionDispatch::IntegrationTest
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
end
