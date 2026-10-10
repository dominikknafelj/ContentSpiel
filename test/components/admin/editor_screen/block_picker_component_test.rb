require "test_helper"

class Admin::EditorScreen::BlockPickerComponentTest < ViewComponent::TestCase
  include ContentHelper

  test "is one dashed Add block row with an inline button per registered type" do
    page = create_page(title: "Picker test")
    render_inline Admin::EditorScreen::BlockPickerComponent.new(page: page, locale: "en")

    assert_selector "#block-picker-end.border-dashed", text: "+ Add block"
    assert_equal BlockTypes.all.map(&:label), Capybara.string(rendered_content).all("#block-picker-end button").map(&:text)
    assert_selector "#block-picker-end form[action$='/content_blocks'] input[name='block[block_type]'][value='post_list']", visible: :all
  end

  # The end-of-list row is where a section is made: it lists the container
  # types with the rest, and sends neither a section nor a column.
  test "the end-of-list row offers Section, and names no section to add into" do
    page = create_page(title: "Picker test")
    render_inline Admin::EditorScreen::BlockPickerComponent.new(page: page, locale: "en")

    assert_selector "#block-picker-end button", text: "Section", exact_text: true
    assert_selector "input[name='block[block_type]'][value='section']", visible: :all
    assert_no_selector "input[name='section_id'], input[name='column']", visible: :all
    assert_no_selector "[role=menu]", visible: :all
  end

  # A lane's "+" (sections spec §4.2): a menu, not a row -- a lane is a
  # column wide -- of every type that may go into a section. Which types
  # those are is asked of the capability, so the list is compared with the
  # registry's and not with names written here.
  test "a lane's picker is a + menu of every type but the containers, posting the section and the column" do
    page = create_page(title: "Picker test")
    section = page.content_blocks.create!(block_type: "section", position: 0)
    render_inline Admin::EditorScreen::BlockPickerComponent.new(page: page, locale: "en", section: section, column: 2)

    picker = "#block-picker-#{section.id}-2"
    assert_selector "#{picker} button[aria-haspopup=menu][aria-label='Add a block to column 2']", text: "+", exact_text: true
    offered = BlockTypes.all.reject { |type| type.capability?(:container) }
    assert_operator offered.size, :<, BlockTypes.all.size
    assert_equal offered.map(&:label), Capybara.string(rendered_content).all("#{picker} [role=menu] form button", visible: :all).map { |button| button.text(:all) }
    assert_no_selector "#{picker} input[name='block[block_type]'][value='section']", visible: :all
    assert_selector "#{picker} form[action$='/content_blocks'][method=post]", count: offered.size, visible: :all
    assert_selector "#{picker} input[name='section_id'][value='#{section.id}']", count: offered.size, visible: :all
    assert_selector "#{picker} input[name='column'][value='2']", count: offered.size, visible: :all
    assert_selector "#{picker} [role=menu][data-action~='click->admin--menu#select']", visible: :all
    assert_no_selector "#block-picker-end, .admin-block-picker", visible: :all
  end

  test "sends no after_id: a new block is appended, and can be moved" do
    page = create_page(title: "Picker test")
    render_inline Admin::EditorScreen::BlockPickerComponent.new(page: page, locale: "en")

    assert_no_selector "input[name='after_id']", visible: :all
    assert_no_selector "[id^='block-picker-after-']", visible: :all
    assert_no_selector "details", visible: :all
  end
end
