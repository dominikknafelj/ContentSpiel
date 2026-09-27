require "test_helper"

class Blocks::RichTextComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  test "renders the block's body in prose" do
    page = root_page
    block = page.content_blocks.create!(block_type: :rich_text, position: 0, body: "<p>Hello there</p>")

    render_inline(Blocks::RichTextComponent.new(block: block, page: page))

    assert_selector ".cs-prose", text: "Hello there"
  end
end
