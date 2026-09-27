require "test_helper"

# Covers the standalone ContentBlock resource's typed `settings` editor
# (open-types spec §6) -- the page form's nested rows get their own coverage
# in AvoPageEditingTest; this is the direct
# /avo/resources/content_blocks/:id form, which used to expose `settings` as
# a raw key_value editor and now renders it through the same typed-fields
# resource tool as Avo::Resources::Post (Avo::ResourceTools::TypedFields).
class AvoContentBlockFieldsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "editor@example.com", password: "password123")
    sign_in_as(@user)
    @page = Page.create!(title: "Home", page_type: :standard)
  end

  test "block_type select offers every registered block type" do
    get "/avo/resources/content_blocks/new"

    assert_response :success
    BlockTypes.all.each do |definition|
      assert_includes response.body, %(<option value="#{definition.name}">#{definition.label}</option>)
    end
  end

  test "a post_list block's form renders its own typed settings inputs" do
    block = @page.content_blocks.create!(block_type: :post_list, position: 0, settings: { "tag" => "rails" })

    get "/avo/resources/content_blocks/#{block.id}/edit"

    assert_response :success
    assert_includes response.body, %(name="content_block[settings][content_type]")
    assert_includes response.body, %(name="content_block[settings][tag]")
    assert_includes response.body, %(name="content_block[settings][limit]")
    assert_match(/name="content_block\[settings\]\[tag\]"[^>]*value="rails"/, response.body)
  end

  test "a rich_text block's form renders no settings inputs" do
    block = @page.content_blocks.create!(block_type: :rich_text, position: 0)

    get "/avo/resources/content_blocks/#{block.id}/edit"

    assert_response :success
    assert_not_includes response.body, "content_block[settings]"
  end

  test "editing a post_list block's settings through the typed inputs casts limit to an integer" do
    block = @page.content_blocks.create!(block_type: :post_list, position: 0)

    put "/avo/resources/content_blocks/#{block.id}", params: { content_block: {
      block_type: "post_list", position: "0", settings: { content_type: "blog", tag: "rails", limit: "3" }
    } }

    assert_response :redirect
    assert_equal({ "content_type" => "blog", "tag" => "rails", "limit" => 3 }, block.reload.settings)
  end

  test "a blank limit is not stored" do
    block = @page.content_blocks.create!(block_type: :post_list, position: 0, settings: { "limit" => 3 })

    put "/avo/resources/content_blocks/#{block.id}", params: { content_block: {
      block_type: "post_list", position: "0", settings: { limit: "" }
    } }

    assert_response :redirect
    assert_not block.reload.settings.key?("limit")
  end
end
