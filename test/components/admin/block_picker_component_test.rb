require "test_helper"

class Admin::BlockPickerComponentTest < ViewComponent::TestCase
  include ContentHelper

  test "is one dashed Add block row with an inline button per registered type" do
    page = create_page(title: "Picker test")
    render_inline Admin::BlockPickerComponent.new(page: page, locale: "en")

    assert_selector "#block-picker-end.border-dashed", text: "+ Add block"
    assert_equal BlockTypes.all.map(&:label), Capybara.string(rendered_content).all("#block-picker-end button").map(&:text)
    assert_selector "#block-picker-end form[action$='/content_blocks'] input[name='block[block_type]'][value='post_list']", visible: :all
  end

  test "sends no after_id: a new block is appended, and can be moved" do
    page = create_page(title: "Picker test")
    render_inline Admin::BlockPickerComponent.new(page: page, locale: "en")

    assert_no_selector "input[name='after_id']", visible: :all
    assert_no_selector "[id^='block-picker-after-']", visible: :all
    assert_no_selector "details", visible: :all
  end
end
