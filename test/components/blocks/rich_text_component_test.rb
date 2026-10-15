require "test_helper"

class Blocks::RichTextComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  test "renders the block's body in prose" do
    page = root_page
    block = page.content_blocks.create!(block_type: :rich_text, position: 0, body: rich_doc("Hello there"))

    render_inline(Blocks::RichTextComponent.new(block: block, page: page))

    assert_selector ".cs-prose", text: "Hello there"
  end

  test "a body that is empty in every language draws nothing" do
    page = root_page
    block = page.content_blocks.create!(block_type: :rich_text, position: 0)

    render_inline(Blocks::RichTextComponent.new(block: block, page: page))

    assert_equal "", rendered_content.strip
  end

  test "a body of only an empty paragraph draws nothing" do
    page = root_page
    block = page.content_blocks.create!(block_type: :rich_text, position: 0, body: { "type" => "doc", "content" => [ { "type" => "paragraph" } ] })

    render_inline(Blocks::RichTextComponent.new(block: block, page: page))

    assert_equal "", rendered_content.strip
  end

  test "a body empty in the visitor's language but written in the fallback language still draws" do
    page = root_page
    block = page.content_blocks.create!(block_type: :rich_text, position: 0)
    block.assign_body(rich_doc("Fallback words"), locale: I18n.default_locale)
    block.save!

    I18n.with_locale(:de) do
      render_inline(Blocks::RichTextComponent.new(block: block, page: page))
    end

    assert_selector ".cs-prose", text: "Fallback words"
  end
end
