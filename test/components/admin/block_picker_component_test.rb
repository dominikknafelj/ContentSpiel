require "test_helper"

class Admin::BlockPickerComponentTest < ViewComponent::TestCase
  include ContentHelper

  test "lists every registered block type as its own button" do
    page = create_page(title: "Picker test")
    render_inline Admin::BlockPickerComponent.new(page: page, locale: "en")

    BlockTypes.all.each { |type| assert_selector "button", text: type.label }
    assert_selector "form[action$='/content_blocks'] input[name='block[block_type]'][value='post_list']", visible: :all
  end

  test "a between-cards picker carries the after_id" do
    page = create_page(title: "Picker test")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_inline Admin::BlockPickerComponent.new(page: page, locale: "en", after_id: block.id)

    assert_selector "form input[name='after_id'][value='#{block.id}']", visible: :all
  end
end
