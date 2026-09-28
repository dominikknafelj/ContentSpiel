require "test_helper"

class Admin::BlockCardComponentTest < ViewComponent::TestCase
  include ContentHelper
  include TestTypes

  test "renders the type label, schema fields and error slots for a registered type" do
    page = create_page(title: "Card test")
    block = page.content_blocks.create!(block_type: "post_list", position: 0, settings: { "limit" => 3 })

    render_inline Admin::BlockCardComponent.new(page: page, block: block, locale: "en")

    assert_text "Post list"
    assert_selector "input[name='block[settings][limit]'][value='3']"
    assert_selector "##{Admin::BlockCardComponent.error_prefix(block)}-limit-errors"
    assert_selector "form[action$='/content_blocks/#{block.id}'][data-controller~='admin--autosave']"
  end

  test "an unregistered block type shows Unavailable type with Delete only" do
    page = create_page(title: "Unavailable test")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    block.update_column(:block_type, "gone/thing")

    render_inline Admin::BlockCardComponent.new(page: page, block: block.reload, locale: "en")

    assert_text "Unavailable type — gone/thing"
    assert_selector "button", text: "Delete"
    refute_text "Duplicate"
    refute_text "Move up"
    refute_selector "form[data-controller~='admin--autosave']"
  end

  test "translated schema fields show the default-locale original in another locale" do
    with_test_types do
      page = create_page(title: "Translated field test")
      block = page.content_blocks.create!(block_type: "test/quote", position: 0, translated_settings: { "en" => { "text" => "Hello" } })

      render_inline Admin::BlockCardComponent.new(page: page, block: block, locale: "de")

      assert_selector "[data-original-for='text']", text: "Hello"
    end
  end

  test "two cards of the same block type never compute the same field id" do
    page = create_page(title: "Id collision test")
    first = page.content_blocks.create!(block_type: "post_list", position: 0)
    second = page.content_blocks.create!(block_type: "post_list", position: 1)

    assert_not_equal Admin::BlockCardComponent.error_prefix(first), Admin::BlockCardComponent.error_prefix(second)
  end
end
