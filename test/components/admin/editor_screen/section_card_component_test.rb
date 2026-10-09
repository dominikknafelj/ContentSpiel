require "test_helper"

class Admin::EditorScreen::SectionCardComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @page = create_page(title: "Section card")
    @section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "three" })
    @text = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 0, body: rich_doc("Hello from a column"))
    @image = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 3, position: 0)
  end

  def render_card
    outline = BlockOutline.new(@page.content_blocks.reload)
    render_inline Admin::EditorScreen::SectionCardComponent.new(page: @page, section: outline.top_level.first, outline: outline, locale: "en")
  end

  test "it is a card of the block list, framed, with one lane per column and a tile per block" do
    render_card

    assert_selector "##{ActionView::RecordIdentifier.dom_id(@section)}.admin-section-card[data-admin--blocks-target='card'][data-container][data-controller~='admin--section']"
    assert_selector "#section-#{@section.id}-lanes > .admin-section-lane > [data-admin--blocks-target='lane']", count: 3
    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", text: "Hello from a column"
    assert_selector "#section-#{@section.id}-lane-2 > *", count: 0
    assert_selector "#section-#{@section.id}-lane-3 > .admin-block-tile", text: "No image chosen"
  end

  test "every block's form is in the panels, hidden" do
    render_card

    assert_selector "#section-#{@section.id}-panels > [data-admin--section-target='panel'][hidden]", count: 2, visible: :all
    assert_selector "#block-#{@text.id}-panel form[data-controller~='admin--autosave']", visible: :all
  end

  test "the header names the section and counts its columns and blocks" do
    render_card

    assert_selector "#section-#{@section.id}-summary", text: "3 columns · 2 blocks"
  end

  test "each lane is labelled with its column for a screen reader and for the stacked layout" do
    render_card

    assert_selector "#section-#{@section.id}-lane-2[aria-label='Column 2']"
  end

  test "the header has the block list's drag handle and a collapse button for the body, and a view-only viewer gets no handle" do
    site_page = @page # `render_inline` takes `@page` for its own Capybara node
    render_card

    assert_selector ".admin-section-card > div:first-child .admin-block-card__handle[aria-label='Move section'][aria-describedby='block-drag-help']"
    assert_selector "button[aria-expanded='true'][aria-controls='section-#{@section.id}-body'][data-action$='admin--blocks#toggle']", text: "Section"
    assert_selector ".admin-section-card > #section-#{@section.id}-body[data-block-body]"

    outline = BlockOutline.new(site_page.content_blocks.reload)
    render_inline Admin::EditorScreen::SectionCardComponent.new(page: site_page, section: outline.top_level.first, outline: outline, locale: "en", editable: false)

    assert_no_selector ".admin-block-card__handle"
    assert_selector "#block-#{@text.id}-panel fieldset[disabled]", visible: :all
    assert_no_selector "form[data-controller~='admin--autosave']", visible: :all
  end

  test "a tile is the block's element: its dom id, a button that names the panel it opens, collapsed" do
    render_card

    tile = "#section-#{@section.id}-lane-3 > ##{ActionView::RecordIdentifier.dom_id(@image)}[role='listitem'][data-block-id='#{@image.id}'][data-admin--section-target='tile'][data-admin--blocks-target='tile']"
    assert_selector tile
    assert_selector "#{tile} > button.admin-block-tile__face[type='button'][aria-expanded='false'][aria-controls='block-#{@image.id}-panel'][data-action='admin--section#toggle']", text: "Image"
    assert_selector "#section-#{@section.id}-lane-3[role='list'][data-section-id='#{@section.id}'][data-column='3']"
  end

  test "the panels are in reading order, column by column" do
    late = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    render_card

    ids = page.all("#section-#{@section.id}-panels > [data-admin--section-target='panel']", visible: :all).map { |panel| panel["data-block-id"].to_i }
    assert_equal [ @text.id, late.id, @image.id ], ids
  end

  test "one column and one block are counted in the singular" do
    @image.destroy!
    @section.update!(settings: { "layout" => "one" })
    render_card

    assert_selector "#section-#{@section.id}-summary", text: "1 column · 1 block", exact_text: true
    assert_selector "#section-#{@section.id}-lanes[data-columns='1'][style*='--lanes: 1']"
  end

  test "a section is drawn as this card on the default language's tab only, and a plain block never" do
    assert Admin::EditorScreen::SectionCardComponent.draws?(@section, locale: "en")
    assert_not Admin::EditorScreen::SectionCardComponent.draws?(@section, locale: "de")
    assert_not Admin::EditorScreen::SectionCardComponent.draws?(@text, locale: "en")
  end
end
