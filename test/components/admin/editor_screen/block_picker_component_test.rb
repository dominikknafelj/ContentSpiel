require "test_helper"

class Admin::EditorScreen::BlockPickerComponentTest < ViewComponent::TestCase
  include ContentHelper

  test "the page's picker is one primary + Add block that opens a menu of every type, each its chip and its name" do
    page = create_page(title: "Picker test")
    render_inline Admin::EditorScreen::BlockPickerComponent.new(page: page, locale: "en")

    assert_selector "#block-picker-end.mt-5", visible: :all
    trigger = Capybara.string(rendered_content).find("#block-picker-end > div > button[aria-haspopup=menu]")
    assert_equal "+ Add block", trigger.text
    assert_equal "Add a block", trigger["aria-label"]
    assert_equal Admin::Ui::ButtonComponent.classes(:primary).split, trigger[:class].split
    assert_no_selector "#block-picker-end.border-dashed, .admin-block-picker", visible: :all
    items = Capybara.string(rendered_content).all("#block-picker-end [role=menu] form button", visible: :all)
    assert_equal BlockTypes.all.map(&:icon), items.map { |button| button.first("[data-block-icon]", minimum: 0, visible: :all)&.[]("data-block-icon") }
    assert_equal BlockTypes.all.map(&:label), items.map { |button| button.text(:all) }
    assert_selector "#block-picker-end form[action$='/content_blocks'] input[name='block[block_type]'][value='post_list']", visible: :all
  end

  test "the menu is three columns at elevation 3, headed Add a block" do
    page = create_page(title: "Picker test")
    render_inline Admin::EditorScreen::BlockPickerComponent.new(page: page, locale: "en")

    classes = Capybara.string(rendered_content).find("#block-picker-end [role=menu]", visible: :all)[:class].split
    %w[grid grid-cols-3 shadow-3 bg-popover rounded-card w-[34rem] max-w-[calc(100vw-2rem)] p-2.5 gap-0.5].each { |name| assert_includes classes, name }
    assert_selector "#block-picker-end [role=menu] > p.text-meta[aria-hidden=true]", text: "Add a block", visible: :all
    assert_selector "#block-picker-end [role=menu][data-action~='click->admin--ui--menu#select']", visible: :all
  end

  # The end-of-list menu is where a section is made: it lists the container
  # types with the rest, and sends neither a section nor a column.
  test "the page's menu offers Section, and names no section to add into" do
    page = create_page(title: "Picker test")
    render_inline Admin::EditorScreen::BlockPickerComponent.new(page: page, locale: "en")

    assert_selector "#block-picker-end [role=menu] button", text: "Section", exact_text: true, visible: :all
    assert_selector "input[name='block[block_type]'][value='section']", visible: :all
    assert_no_selector "input[name='section_id'], input[name='column']", visible: :all
  end

  # A lane's "+" (sections spec §4.2): a menu, not a row -- a lane is a
  # column wide -- of every type that may go into a section. Which types
  # those are is asked of the capability, so the list is compared with the
  # registry's and not with names written here.
  test "a lane's picker is + Add, named for its column, and offers no Section: every type but the containers, posting the section and the column" do
    page = create_page(title: "Picker test")
    section = page.content_blocks.create!(block_type: "section", position: 0)
    render_inline Admin::EditorScreen::BlockPickerComponent.new(page: page, locale: "en", section: section, column: 2)

    picker = "#block-picker-#{section.id}-2"
    assert_selector "#{picker} button[aria-haspopup=menu][aria-label='Add a block to column 2']", text: "+ Add", exact_text: true
    assert_equal Admin::Ui::ButtonComponent.classes(:tertiary, size: :small).split, Capybara.string(rendered_content).find("#{picker} button[aria-haspopup=menu]")[:class].split
    assert_no_selector "#{picker} [role=menu].grid", visible: :all
    offered = BlockTypes.all.reject { |type| type.capability?(:container) }
    assert_operator offered.size, :<, BlockTypes.all.size
    assert_equal offered.map(&:label), Capybara.string(rendered_content).all("#{picker} [role=menu] form button", visible: :all).map { |button| button.text(:all) }
    assert_no_selector "#{picker} input[name='block[block_type]'][value='section']", visible: :all
    assert_selector "#{picker} form[action$='/content_blocks'][method=post]", count: offered.size, visible: :all
    assert_selector "#{picker} [role=menu] form button [data-block-icon]", count: offered.size, visible: :all
    assert_selector "#{picker} input[name='section_id'][value='#{section.id}']", count: offered.size, visible: :all
    assert_selector "#{picker} input[name='column'][value='2']", count: offered.size, visible: :all
    assert_selector "#{picker} [role=menu][data-action~='click->admin--ui--menu#select']", visible: :all
    assert_no_selector "#block-picker-end, .admin-block-picker", visible: :all
  end

  test "offers no between-cards picker: a new block is appended, and can be moved" do
    page = create_page(title: "Picker test")
    render_inline Admin::EditorScreen::BlockPickerComponent.new(page: page, locale: "en")

    assert_no_selector "[id^='block-picker-after-']", visible: :all
    assert_no_selector "details", visible: :all
  end
end
