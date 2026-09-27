require "test_helper"

class ContentBlocks::SaveTest < ActiveSupport::TestCase
  test "appends to the end of the page's blocks when position is nil" do
    page = create_page(title: "Page")

    first = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: "<p>One</p>" } })
    second = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: "<p>Two</p>" } })

    assert first.ok?
    assert second.ok?
    assert_equal 0, first.record.position
    assert_equal 1, second.record.position
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
end
