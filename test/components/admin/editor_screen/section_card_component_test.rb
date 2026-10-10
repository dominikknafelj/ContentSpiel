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
    assert_selector "#section-#{@section.id}-lanes[data-admin--section-target='lanes'] > .admin-section-lane > [data-admin--blocks-target='lane']", count: 3
    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", text: "Hello from a column"
    assert_selector "#section-#{@section.id}-lane-2 > *", count: 0
    assert_selector "#section-#{@section.id}-lane-3 > .admin-block-tile", text: "No image chosen"
  end

  test "every block's form is in the panels, hidden" do
    render_card

    assert_selector "#section-#{@section.id}-panels > [data-admin--section-target='panel'][hidden]", count: 2, visible: :all
    assert_selector "#block-#{@text.id}-panel form[data-controller~='admin--autosave']", visible: :all
  end

  # The "+" at the end of each lane (spec §4.2) is in the lane's wrapper,
  # after the lane and never in it: a lane's children are exactly its tiles.
  test "each lane ends with its picker, outside the lane element, for a viewer who can edit" do
    as(users(:one), channel: :admin) { render_card }

    (1..3).each do |column|
      assert_selector "#section-#{@section.id}-lanes > .admin-section-lane > [data-admin--blocks-target='lane'] + #block-picker-#{@section.id}-#{column}"
      assert_no_selector "#section-#{@section.id}-lane-#{column} #block-picker-#{@section.id}-#{column}", visible: :all
    end
    assert_selector "#section-#{@section.id}-lane-1 > *", count: 1
    assert_selector "#section-#{@section.id}-lane-2 > *", count: 0, visible: :all
  end

  test "a viewer who can't edit gets no picker in a lane" do
    as(users(:reader), channel: :admin) { render_card }

    assert_selector "#section-#{@section.id}-lanes [data-admin--blocks-target='lane']", count: 3
    assert_no_selector "[id^='block-picker-']", visible: :all
  end

  # The notes handoff's decision 10: a section takes no notes of its own. Its
  # card has no marker and its menu no "Add note", for an editor and for a
  # viewer who can only read; the only markers and "Add note" items in it are
  # its tiles'.
  test "a section's card offers no way to add a note on the section itself, to an editor or to a view-only viewer" do
    record = @page
    [ users(:one), users(:reader) ].each do |viewer|
      @page = record # the test helper's own `page` is kept in the same variable after a render
      as(viewer, channel: :admin) { render_card }

      assert_no_selector "#notes-marker-ContentBlock-#{@section.id}", visible: :all
      assert_no_selector "[data-notes-key='ContentBlock-#{@section.id}']", visible: :all
      assert_equal [ @text, @image ].map { |block| "ContentBlock-#{block.id}" }.sort,
        page.all("[data-admin--notes-target=marker]", visible: :all).map { |marker| marker["data-notes-key"] }.sort
      assert_equal [ @text, @image ].map { |block| "ContentBlock-#{block.id}" }.sort,
        page.all("button[data-notes-compose]", visible: :all).map { |item| item["data-notes-key"] }.sort
      assert_no_selector "button[aria-label='Section actions'] + [role=menu] button", text: "Add note", visible: :all
    end
    # A view-only viewer's section has no menu of its own at all.
    assert_no_selector "button[aria-label='Section actions']", visible: :all
  end

  test "the section's delete dialog asks for the sentence that counts its blocks' notes, and Remove section, keep blocks has no dialog" do
    as(users(:one), channel: :admin) { render_card }

    assert_selector "#delete-section-#{@section.id} p[hidden][data-admin--notes-target=warning][data-notes-warning=section][data-notes-within='#{ActionView::RecordIdentifier.dom_id(@section)}']", visible: :all
    assert_selector "dialog", visible: :all, count: 3 # the section's delete dialog and one per tile
    assert_selector "form[data-controller='admin--queue-hold'] input[name=keep_blocks]", visible: :all
  end

  # The header's count is drawn by the one method a stream redraws it with
  # (`Admin::ContentBlocksController#section_count_streams`).
  test "the summary a stream replaces is the one the card draws" do
    render_card
    card = Capybara.string(rendered_content).find("#section-#{@section.id}-summary")

    alone = Capybara.string(render_inline(Admin::EditorScreen::SectionCardComponent.summary(section: @section, count: 2)).to_html).find("#section-#{@section.id}-summary")

    assert_equal [ card.text, card[:class] ], [ alone.text, alone[:class] ]
    assert_equal "3 columns · 2 blocks", alone.text
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

  test "the header carries the section's own autosaving form: layout, background, width" do
    render_card

    assert_selector "form#section-#{@section.id}-form[data-controller~='admin--autosave'][action$='/content_blocks/#{@section.id}']"
    assert_selector "input[type=hidden][name='block[settings][layout]'][value='three']", visible: :all
    assert_selector "select[name='block[settings][background]'] option[selected][value='none']"
    assert_selector "select[name='block[settings][width]'] option", count: 2
    assert_selector "button[data-action='admin--section#chooseLayout'][data-admin--section-layout-param]", count: 6, visible: :all
    assert_selector "button[data-admin--section-layout-param='three'][aria-current='true']", visible: :all
    assert_selector "#block-#{@section.id}-save-status"
  end

  # What `Admin::ContentBlocksController#update` answers into: the base the
  # stale-save guard compares, and one error slot per setting.
  test "the form has the block's base field and an error slot for each of its three settings" do
    render_card

    form = "form#section-#{@section.id}-form"
    assert_selector "#{form} input[type=hidden][name='base_updated_at']#block-#{@section.id}-base-updated-at[value='#{@section.reload.updated_at.iso8601(6)}']", visible: :all
    assert_selector "#{form} input#block-#{@section.id}-layout[name='block[settings][layout]']", visible: :all
    %w[layout background width].each do |name|
      assert_selector "#{form} ##{Admin::Ui::FieldComponent.error_id("block-#{@section.id}", name)}", visible: :all
    end
    assert_selector "#{form} select#block-#{@section.id}-background[aria-label='Background']"
    assert_selector "#{form} select#block-#{@section.id}-width[aria-label='Width']"
  end

  # A section just made stores no settings: the form shows, and sends, what
  # the type reads for it -- or its first save would be refused for a layout
  # it never had the chance to choose.
  test "a section with no stored settings has the schema's defaults in its form" do
    @image.destroy!
    @section.update_column(:settings, {})
    render_card

    assert_selector "input[type=hidden][name='block[settings][layout]'][value='two']", visible: :all
    assert_selector "button[data-admin--section-layout-param='two'][aria-current='true']", visible: :all
    assert_selector "select[name='block[settings][background]'] option[selected][value='none']"
    assert_selector "select[name='block[settings][width]'] option[selected][value='content']"
  end

  # The layout menu is replaced by a stream after a save, so it has its own
  # wrapper; the hidden input the pick is written into is not in it.
  test "the layout menu is its own element, named, each choice a diagram of its columns with its name for a screen reader" do
    render_card

    menu = "#section-#{@section.id}-layout-menu"
    assert_selector "#{menu}[data-admin--section-target='layoutMenu'] button[aria-haspopup='menu'][aria-label='Layout']", text: "Layout"
    assert_no_selector "#{menu} input", visible: :all
    assert_selector "#{menu} button[data-admin--section-layout-param='one_two'] .admin-layout-diagram[aria-hidden='true'] > span", count: 2, visible: :all
    assert_selector "#{menu} button[data-admin--section-layout-param='one_two'] .sr-only", text: "One third, two thirds", visible: :all
    assert_selector "#{menu} button[aria-current='false']", count: 5, visible: :all
    # The trigger shows the current layout: three equal columns.
    assert_selector "#{menu} button[aria-haspopup='menu'] .admin-layout-diagram > span", count: 3
  end

  test "the menu moves, duplicates, removes keeping the blocks, and deletes behind a dialog that counts them" do
    render_card

    assert_selector "button[data-move='up']", text: "Move up", visible: :all
    assert_selector "form[action$='/content_blocks/#{@section.id}/duplicate']", visible: :all
    assert_selector "form[action$='/content_blocks/#{@section.id}'] input[name='keep_blocks'][value='1']", visible: :all
    assert_selector "#section-#{@section.id}-delete-count", text: "This also deletes the 2 blocks in it.", visible: :all
  end

  test "the section's menu is named, its Move items follow the card's place, and Delete opens the section's own dialog" do
    outline = BlockOutline.new(@page.content_blocks.reload)
    render_inline Admin::EditorScreen::SectionCardComponent.new(page: @page, section: outline.top_level.first, outline: outline, locale: "en", first: true, last: false)

    header = ".admin-section-card > div:first-child"
    assert_selector "#{header} button[aria-haspopup='menu'][aria-label='Section actions']", text: "⋯"
    assert_selector "#{header} button[data-move='up'][disabled][data-action='click->admin--blocks#moveUp']", visible: :all
    assert_selector "#{header} button[data-move='down']:not([disabled])[data-action='click->admin--blocks#moveDown']", text: "Move down", visible: :all
    assert_selector "#{header} button[data-admin--dialog-id-param='delete-section-#{@section.id}']", text: "Delete section and its blocks…", visible: :all
    assert_selector "dialog#delete-section-#{@section.id} form[action$='/content_blocks/#{@section.id}'] button[type=submit]", text: "Delete section", visible: :all
    assert_no_selector "dialog#delete-section-#{@section.id} input[name='keep_blocks']", visible: :all
    # No form inside the settings form: a nested form is dropped by the parser.
    assert_no_selector "form#section-#{@section.id}-form form", visible: :all
  end

  test "the delete dialog counts one block in the singular and says nothing of blocks for an empty section" do
    site_page = @page # `render_inline` takes `@page` for its own Capybara node
    @image.destroy!
    render_card
    assert_selector "#section-#{@section.id}-delete-count", text: "This also deletes the 1 block in it.", exact_text: true, visible: :all

    @page = site_page
    @text.destroy!
    render_card
    assert_selector "p#section-#{@section.id}-delete-count", text: "", exact_text: true, visible: :all
  end

  # The line a delete or an add inside the section replaces
  # (`Admin::ContentBlocksController#section_count_streams`).
  test "the delete count a stream replaces is the one the card draws" do
    render_card
    card = Capybara.string(rendered_content).find("#section-#{@section.id}-delete-count", visible: :all)

    alone = Capybara.string(render_inline(Admin::EditorScreen::SectionCardComponent.delete_count(section: @section, count: 2)).to_html).find("#section-#{@section.id}-delete-count", visible: :all)

    assert_equal [ card.text(:all), card[:class] ], [ alone.text(:all), alone[:class] ]
    assert_equal "section-#{@section.id}-delete-count", Admin::EditorScreen::SectionCardComponent.delete_count_id(@section)
  end

  test "a viewer who can't edit the page gets no form controls, no menu and no handle" do
    outline = BlockOutline.new(@page.content_blocks.reload)
    render_inline Admin::EditorScreen::SectionCardComponent.new(page: @page, section: outline.top_level.first, outline: outline, locale: "en", editable: false)

    assert_no_selector ".admin-block-card__handle"
    assert_no_selector "[aria-label='Section actions']"
    assert_selector "fieldset[disabled] select[name='block[settings][background]']"
    assert_selector "fieldset[disabled] button[aria-haspopup='menu'][aria-label='Layout']"
    assert_no_selector "form[data-controller~='admin--autosave']"
    assert_no_selector "dialog#delete-section-#{@section.id}", visible: :all
  end

  # One string for a menu item's look, wherever a menu of the block list is drawn.
  test "the lane picker's and the section menu's items use the block card's menu item class" do
    assert_same Admin::EditorScreen::BlockCardComponent::MENU_ITEM_CLASS, Admin::EditorScreen::BlockPickerComponent::MENU_ITEM_CLASS
  end

  test "a tile is the block's element: its dom id, a button that names the panel it opens, collapsed" do
    render_card

    tile = "#section-#{@section.id}-lane-3 > ##{ActionView::RecordIdentifier.dom_id(@image)}[role='listitem'][data-block-id='#{@image.id}'][data-admin--section-target='tile'][data-admin--blocks-target='tile']"
    assert_selector tile
    assert_selector "#{tile} > button.admin-block-tile__face[type='button'][aria-expanded='false'][aria-controls='block-#{@image.id}-panel'][data-action='admin--section#toggle']", text: "Image"
    assert_selector "#section-#{@section.id}-lane-3[role='list'][data-section-id='#{@section.id}'][data-column='3']"
  end

  # Plan D9: a tile is dragged by the pointer only. Its grip is no button and
  # is hidden from a screen reader, which would otherwise be offered a control
  # the keyboard can't work; the keyboard's moves are in the tile's menu.
  test "a tile has a grip to drag it by, before its face, that is no control" do
    as(users(:one), channel: :admin) { render_card }

    tile = "##{ActionView::RecordIdentifier.dom_id(@image)}"
    assert_selector "#{tile} > span.admin-block-tile__grip[aria-hidden='true']:first-child", visible: :all
    assert_no_selector "#{tile} > .admin-block-tile__grip[tabindex], #{tile} > button.admin-block-tile__grip", visible: :all
    assert_selector "#{tile} > .admin-block-tile__grip + button.admin-block-tile__face"
  end

  test "a viewer who can't edit the page gets a tile with no grip" do
    outline = BlockOutline.new(@page.content_blocks.reload)
    render_inline Admin::EditorScreen::SectionCardComponent.new(page: @page, section: outline.top_level.first, outline: outline, locale: "en", editable: false)

    assert_no_selector ".admin-block-tile__grip", visible: :all
    assert_selector "##{ActionView::RecordIdentifier.dom_id(@image)} > button.admin-block-tile__face"
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

  # One rule for the page view and for a card streamed in (`Admin
  # ::ContentBlocksController#card_for`): a top-level block is drawn as a
  # section when it is a container, or holds blocks although its type is gone.
  test "a block is drawn as a section when it is a container or still holds blocks, and a plain block never" do
    outline = BlockOutline.new(@page.content_blocks.reload)
    section = outline.top_level.first
    assert Admin::EditorScreen::SectionCardComponent.draws?(section, outline: outline)
    assert_not Admin::EditorScreen::SectionCardComponent.draws?(@text, outline: outline)

    @section.update_columns(block_type: "gone/section")
    outline = BlockOutline.new(@page.content_blocks.reload)
    assert Admin::EditorScreen::SectionCardComponent.draws?(outline.top_level.first, outline: outline)

    [ @text, @image ].each(&:destroy!)
    outline = BlockOutline.new(@page.content_blocks.reload)
    assert_not Admin::EditorScreen::SectionCardComponent.draws?(outline.top_level.first, outline: outline)
  end

  # ---- A section whose type is gone (sections spec §6) ----------------------

  test "a section whose type is gone is the Unavailable type card with its blocks listed under it" do
    @section.update_columns(block_type: "gone/section")
    as(users(:one), channel: :admin) { render_card }

    assert_selector ".admin-section-card.border-danger[data-container][data-admin--blocks-target='card']", text: "Unavailable type — gone/section"
    assert_selector ".admin-section-card", text: "Its blocks are still here. Remove the section and keep them, move them out one by one, or delete it with them."
    assert_selector ".admin-block-tile", count: 2
    assert_selector "[data-admin--blocks-target='lane'][data-no-drop]", count: 2
    assert_no_selector "[data-admin--blocks-target='lane']:not([data-no-drop])", visible: :all
    assert_no_selector "form#section-#{@section.id}-form", visible: :all
    assert_selector "button[type='submit']", text: "Remove section, keep blocks", exact_text: true
    assert_selector "button", text: "Delete section and its blocks…", exact_text: true
    assert_no_selector "button", text: "Delete block…", exact_text: true
  end

  # A tile's lane says where its block really is: that is what a move out of
  # the section names as where the block came from (`moved_from`).
  test "its lanes are the columns its blocks are stored in, each closed to drops and with no picker" do
    @section.update_columns(block_type: "gone/section")
    as(users(:one), channel: :admin) { render_card }

    assert_selector "#section-#{@section.id}-lanes[data-columns='2']"
    assert_selector "#section-#{@section.id}-lane-1[data-column='1'][data-section-id='#{@section.id}'] > ##{ActionView::RecordIdentifier.dom_id(@text)}"
    assert_selector "#section-#{@section.id}-lane-3[data-column='3'] > ##{ActionView::RecordIdentifier.dom_id(@image)}"
    assert_no_selector "#section-#{@section.id}-lane-2", visible: :all
    assert_no_selector "[id^='block-picker-']", visible: :all
    assert_selector "#section-#{@section.id}-panels > [data-admin--section-target='panel']", count: 2, visible: :all
  end

  # Its two actions are a section's two removals, under the menu's own words:
  # the one that keeps the blocks is a form of its own, sent with
  # `keep_blocks` and only on a settled screen (`admin--queue-hold`: its
  # answer replaces the blocks' forms); the other opens the dialog.
  test "it has no handle, no menu and no settings; its two actions are Remove section, keep blocks and the dialog that counts its blocks" do
    @section.update_columns(block_type: "gone/section")
    as(users(:one), channel: :admin) { render_card }
    header = "##{ActionView::RecordIdentifier.dom_id(@section)} > div:first-child"

    assert_no_selector ".admin-block-card__handle", visible: :all
    assert_no_selector "button[aria-label='Section actions']", visible: :all
    assert_no_selector "select, [data-admin--section-target='layoutMenu']", visible: :all
    assert_no_selector "#section-#{@section.id}-summary", visible: :all
    keep = "#{header} form[action$='/content_blocks/#{@section.id}'][data-controller='admin--queue-hold'][data-action='submit->admin--queue-hold#submit']"
    assert_selector "#{keep} input[name='_method'][value='delete']", visible: :all
    assert_selector "#{keep} input[name='keep_blocks'][value='1']", visible: :all
    assert_selector "#{keep} button[type='submit']", text: "Remove section, keep blocks", exact_text: true
    assert_selector "#{header} button[data-admin--dialog-id-param='delete-section-#{@section.id}']", text: "Delete section and its blocks…", exact_text: true
    assert_selector "#{header} button", count: 2
    assert_selector "dialog#delete-section-#{@section.id} #section-#{@section.id}-delete-count", text: "This also deletes the 2 blocks in it.", visible: :all
    assert_selector "dialog#delete-section-#{@section.id} form[action$='/content_blocks/#{@section.id}'] input[name='_method'][value='delete']", visible: :all
    assert_no_selector "dialog input[name='keep_blocks']", visible: :all
    assert_selector "input[name='keep_blocks']", count: 1, visible: :all
  end

  test "a viewer who can't edit sees the unavailable section and its tiles, and nothing that deletes" do
    @section.update_columns(block_type: "gone/section")
    as(users(:reader), channel: :admin) { render_card }

    assert_selector ".admin-section-card.border-danger", text: "Unavailable type — gone/section"
    assert_selector ".admin-block-tile", count: 2
    assert_no_selector "button", text: "Remove section, keep blocks", visible: :all
    assert_no_selector "button", text: "Delete section and its blocks…", visible: :all
    assert_no_selector "input[name='keep_blocks']", visible: :all
    assert_no_selector "form[data-controller='admin--queue-hold']", visible: :all
    assert_no_selector "dialog", visible: :all
    assert_no_selector ".admin-block-tile__grip", visible: :all
  end
end
