require "test_helper"

class Admin::EditorScreen::SectionCardComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @editor_page = create_page(title: "Section card")
    @section = @editor_page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "three" })
    @text = @editor_page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 0, body: rich_doc("Hello from a column"))
    @image = @editor_page.content_blocks.create!(block_type: "image", section: @section, section_column: 3, position: 0)
  end

  def render_card
    outline = BlockOutline.new(@editor_page.content_blocks.reload)
    render_inline Admin::EditorScreen::SectionCardComponent.new(page: @editor_page, section: outline.top_level.first, outline: outline, locale: "en")
  end

  test "it is a card of the block list, framed, with one lane per column and a tile per block" do
    render_card

    assert_selector "##{ActionView::RecordIdentifier.dom_id(@section)}.admin-section-card[data-admin--editor--blocks-target='card'][data-container][data-controller~='admin--editor--section']"
    assert_selector "#section-#{@section.id}-lanes[data-admin--editor--section-target='lanes'] > .admin-section-lane > [data-admin--editor--blocks-target='lane']", count: 3
    assert_selector "#section-#{@section.id}-lane-1 > .admin-block-tile", text: "Hello from a column"
    assert_selector "#section-#{@section.id}-lane-2 > *", count: 0
    assert_selector "#section-#{@section.id}-lane-3 > .admin-block-tile", text: "No image chosen"
  end

  # The frame and its head are the stylesheet's (`.admin-section-card`,
  # `__head`): the card carries no border, radius or ground utility.
  test "a section is a structure frame with a tinted head holding its chip, name, words and count" do
    render_card

    card = page.find("##{ActionView::RecordIdentifier.dom_id(@section)}")
    assert_equal "admin-block-card admin-section-card", card[:class]
    assert_nil card["data-card-edge"]
    head = "##{ActionView::RecordIdentifier.dom_id(@section)} > #section-#{@section.id}-header.admin-section-card__head"
    assert_selector head
    parts = page.all("#{head} > *").map do |part|
      if part[:class].to_s.include?("admin-block-card__handle") then :handle
      elsif part["data-block-icon"] then :chip
      elsif part["data-action"].to_s.include?("admin--editor--blocks#toggle") then :name
      elsif part[:id] == "section-#{@section.id}-words" then :words
      elsif part[:id] == "section-#{@section.id}-summary" then :count
      elsif part["data-controller"].to_s.include?("admin--ui--menu") then :menu
      end
    end
    assert_equal %i[handle chip name words count menu], parts
    assert_selector "#{head} [data-block-icon=columns_2]"
    assert_selector "#{head} #section-#{@section.id}-summary.text-count", text: "2 blocks", exact_text: true
    assert_selector "#{head} #section-#{@section.id}-words button.admin-section-word", text: "3 columns"
  end

  test "the settings form sits in a hidden region under the head, with its id and every editing mark" do
    render_card

    card = "##{ActionView::RecordIdentifier.dom_id(@section)}"
    region = "#{card} > #section-#{@section.id}-settings"
    assert_selector "#{region}[hidden].admin-section-card__settings.mx-3.mb-3.rounded-card.bg-rail.p-3[data-admin--editor--section-target='settings']", visible: :all
    assert_equal "section-#{@section.id}-settings", Admin::EditorScreen::SectionCardComponent.settings_id(@section)
    assert_equal "section-#{@section.id}-words", Admin::EditorScreen::SectionCardComponent.words_id(@section)
    # One form, in the region and nowhere else, with the marks `editing/merge` reads.
    assert_selector "form#section-#{@section.id}-form", count: 1, visible: :all
    assert_selector "#{region} > form#section-#{@section.id}-form[data-controller~='admin--saving--autosave'][data-editing-unit]" \
      "[data-editing-subject='#{Editing.key(@section)}'][data-editing-version]", visible: :all
    assert_no_selector "#section-#{@section.id}-header form#section-#{@section.id}-form", visible: :all
    %w[layout background width anchor].each { |name| assert_selector "#{region} [name='block[settings][#{name}]']", visible: :all }
    assert_selector "#{region} #section-#{@section.id}-layout-menu", visible: :all
    assert_selector "#{region} #block-#{@section.id}-save-status", visible: :all
    %w[layout background width style anchor].each { |name| assert_selector "#{region} ##{Admin::Ui::FieldComponent.error_id("block-#{@section.id}", name)}", visible: :all }
    assert_selector "#{region} button[data-action='admin--editor--section#closeSettings']", text: "Close", visible: :all
    # Head, the hold strip's slot and its announcer, the region, then the body.
    order = page.all("#{card} > *", visible: :all).map { |part| part[:id] || (part["data-editing-announcer"] ? "announcer" : part.tag_name) }
    assert_equal [ "section-#{@section.id}-header", "block-#{@section.id}-hold", "announcer", "section-#{@section.id}-settings", "section-#{@section.id}-body" ], order.first(5)
  end

  test "a held section's region holds the read-only fieldset and its strip stays above the region" do
    dana = users(:two)
    dana.update!(name: "Dana Weiss")
    reserve(@section, @editor_page, dana, "tab-bbbbbbbb")
    render_card_for(users(:one), "tab-aaaaaaaa")

    card = "##{ActionView::RecordIdentifier.dom_id(@section)}"
    assert_selector "#{card}[data-card-edge='held']"
    assert_selector "#{card} > #block-#{@section.id}-hold [data-editing-kind=held]", text: "Dana Weiss is editing this block"
    assert_selector "#{card} > #section-#{@section.id}-settings[hidden] > form#section-#{@section.id}-form[data-editing-held=true] fieldset.admin-held", visible: :all
    strip, region = %W[block-#{@section.id}-hold section-#{@section.id}-settings].map { |id| page.all("#{card} > *", visible: :all).index { |part| part[:id] == id } }
    assert_operator strip, :<, region

    outline = BlockOutline.new(@editor_page.content_blocks.reload)
    render_inline Admin::EditorScreen::SectionCardComponent.new(page: @editor_page, section: outline.top_level.first, outline: outline, locale: "en", editable: false)
    assert_selector "#section-#{@section.id}-settings fieldset.admin-view-only[disabled]", visible: :all
    assert_selector "#section-#{@section.id}-words button.admin-section-word", count: 3
  end

  # #146, decided as a note and not a declaration: the CMS cannot know what a
  # style draws, so a style other than the default only gets the words "may".
  test "a style other than the default shows a help line that it may set its own layout, background or width; the default and a dropped name do not" do
    with_section_grid_theme do
      @section.update!(settings: { "layout" => "three", "style" => "grid_six" })
      render_card
      assert_selector "form [data-template-field='style-note']:not([hidden])", text: "This style may set its own layout, background or width.", visible: :all
      assert_selector "select[data-admin--editor--template-fields-target='select'] option[value='grid_six'][data-fields='style-note']", visible: :all
      assert_selector "select[data-admin--editor--template-fields-target='select'] option[value='']:not([data-fields])", visible: :all

      @section.update!(settings: { "layout" => "three" })
      render_card
      assert_selector "[data-template-field='style-note'][hidden]", visible: :all

      @section.update_columns(settings: { "layout" => "three", "style" => "dropped_style" }) # version: none (a stored name the theme dropped)
      render_card
      assert_selector "[data-template-field='style-note'][hidden]", visible: :all
    end
  end

  test "a theme that declares no style draws no style select and no help line" do
    render_card
    assert_no_selector "[data-template-field='style-note']", visible: :all
  end

  test "every block's form is in the panels, hidden" do
    render_card

    assert_selector "#section-#{@section.id}-panels > [data-admin--editor--section-target='panel'][hidden]", count: 2, visible: :all
    assert_selector "#block-#{@text.id}-panel form[data-controller~='admin--saving--autosave']", visible: :all
  end

  # The "+" at the end of each lane (spec §4.2) is in the lane's wrapper,
  # after the lane and never in it: a lane's children are exactly its tiles.
  test "each lane ends with its picker, outside the lane element, for a viewer who can edit" do
    as(users(:one), channel: :admin) { render_card }

    (1..3).each do |column|
      assert_selector "#section-#{@section.id}-lanes > .admin-section-lane > [data-admin--editor--blocks-target='lane'] + #block-picker-#{@section.id}-#{column}"
      assert_no_selector "#section-#{@section.id}-lane-#{column} #block-picker-#{@section.id}-#{column}", visible: :all
    end
    assert_selector "#section-#{@section.id}-lane-1 > *", count: 1
    assert_selector "#section-#{@section.id}-lane-2 > *", count: 0, visible: :all
  end

  test "a viewer who can't edit gets no picker in a lane" do
    as(users(:reader), channel: :admin) { render_card }

    assert_selector "#section-#{@section.id}-lanes [data-admin--editor--blocks-target='lane']", count: 3
    assert_no_selector "[id^='block-picker-']", visible: :all
  end

  # The notes handoff's decision 10: a section takes no notes of its own. Its
  # card has no marker and its menu no "Add note", for an editor and for a
  # viewer who can only read; the only markers and "Add note" items in it are
  # its tiles'.
  test "a section's card offers no way to add a note on the section itself, to an editor or to a view-only viewer" do
    [ users(:one), users(:reader) ].each do |viewer|
      as(viewer, channel: :admin) { render_card }

      assert_no_selector "#notes-marker-ContentBlock-#{@section.id}", visible: :all
      assert_no_selector "[data-notes-key='ContentBlock-#{@section.id}']", visible: :all
      assert_equal [ @text, @image ].map { |block| "ContentBlock-#{block.id}" }.sort,
        page.all("[data-admin--notes--drawer-target=marker]", visible: :all).map { |marker| marker["data-notes-key"] }.sort
      assert_equal [ @text, @image ].map { |block| "ContentBlock-#{block.id}" }.sort,
        page.all("button[data-notes-compose]", visible: :all).map { |item| item["data-notes-key"] }.sort
      assert_no_selector "button[aria-label='Section actions'] + [role=menu] button", text: "Add note", visible: :all
    end
    # A view-only viewer's section has no menu of its own at all.
    assert_no_selector "button[aria-label='Section actions']", visible: :all
  end

  test "the section's delete dialog asks for the sentence that counts its blocks' notes, and Remove section, keep blocks has no dialog" do
    as(users(:one), channel: :admin) { render_card }

    assert_selector "#delete-section-#{@section.id} p[hidden][data-admin--notes--drawer-target=warning][data-notes-warning=section][data-notes-within='#{ActionView::RecordIdentifier.dom_id(@section)}']", visible: :all
    assert_selector "dialog", visible: :all, count: 3 # the section's delete dialog and one per tile
    assert_selector "form[data-controller='admin--saving--queue-hold'] input[name=keep_blocks]", visible: :all
  end

  # The header's count is drawn by the one method a stream redraws it with
  # (`Admin::Answers::BlockDrawing#section_count_streams`).
  test "the summary a stream replaces is the one the card draws" do
    render_card
    card = Capybara.string(rendered_content).find("#section-#{@section.id}-summary")

    alone = Capybara.string(render_inline(Admin::EditorScreen::SectionCardComponent.summary(section: @section, count: 2)).to_html).find("#section-#{@section.id}-summary")

    assert_equal [ card.text, card[:class] ], [ alone.text, alone[:class] ]
    assert_equal "2 blocks", alone.text
  end

  test "the header names the section and counts its blocks; its columns are a word" do
    render_card

    assert_selector "#section-#{@section.id}-summary", text: "2 blocks", exact_text: true
    assert_selector "#section-#{@section.id}-words button", text: "3 columns"
  end

  test "each lane is labelled with its column for a screen reader and for the stacked layout" do
    render_card

    assert_selector "#section-#{@section.id}-lane-2[aria-label='Column 2']"
  end

  test "the header has the block list's drag handle and a collapse button for the body, and a view-only viewer gets no handle" do
    render_card

    assert_selector ".admin-section-card > div:first-child .admin-block-card__handle[aria-label='Move section'][aria-describedby='block-drag-help']"
    assert_selector "button[aria-expanded='true'][aria-controls='section-#{@section.id}-body'][data-action$='admin--editor--blocks#toggle']", text: "Section"
    assert_selector ".admin-section-card > #section-#{@section.id}-body[data-block-body]"

    outline = BlockOutline.new(@editor_page.content_blocks.reload)
    render_inline Admin::EditorScreen::SectionCardComponent.new(page: @editor_page, section: outline.top_level.first, outline: outline, locale: "en", editable: false)

    assert_no_selector ".admin-block-card__handle"
    assert_selector "#block-#{@text.id}-panel fieldset[disabled]", visible: :all
    assert_no_selector "form[data-controller~='admin--saving--autosave']", visible: :all
  end

  test "the header carries the section's own autosaving form: layout, background, width" do
    render_card

    assert_selector "form#section-#{@section.id}-form[data-controller~='admin--saving--autosave'][action$='/content_blocks/#{@section.id}']", visible: :all
    assert_selector "input[type=hidden][name='block[settings][layout]'][value='three']", visible: :all
    assert_selector "select[name='block[settings][background]'] option[selected][value='none']", visible: :all
    assert_selector "select[name='block[settings][width]'] option", count: 2, visible: :all
    assert_selector "button[data-action='admin--editor--section#chooseLayout'][data-admin--editor--section-layout-param]", count: 6, visible: :all
    assert_selector "button[data-admin--editor--section-layout-param='three'][aria-current='true']", visible: :all
    assert_selector "#block-#{@section.id}-save-status", visible: :all
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
    assert_selector "#{form} select#block-#{@section.id}-background[aria-label='Background']", visible: :all
    assert_selector "#{form} select#block-#{@section.id}-width[aria-label='Width']", visible: :all
  end

  # A section just made stores no settings: the form shows, and sends, what
  # the type reads for it -- or its first save would be refused for a layout
  # it never had the chance to choose.
  test "a section with no stored settings has the schema's defaults in its form" do
    @image.destroy!
    @section.update_column(:settings, {})
    render_card

    assert_selector "input[type=hidden][name='block[settings][layout]'][value='two']", visible: :all
    assert_selector "button[data-admin--editor--section-layout-param='two'][aria-current='true']", visible: :all
    assert_selector "select[name='block[settings][background]'] option[selected][value='none']", visible: :all
    assert_selector "select[name='block[settings][width]'] option[selected][value='content']", visible: :all
  end

  # The layout menu is replaced by a stream after a save, so it has its own
  # wrapper; the hidden input the pick is written into is not in it.
  test "the layout menu is its own element, named, each choice a diagram of its columns with its name for a screen reader" do
    render_card

    menu = "#section-#{@section.id}-layout-menu"
    assert_selector "#{menu}[data-admin--editor--section-target='layoutMenu'] button[aria-haspopup='menu'][aria-label='Layout']", text: "Layout", visible: :all
    assert_no_selector "#{menu} input", visible: :all
    assert_selector "#{menu} button[data-admin--editor--section-layout-param='one_two'] .admin-layout-diagram[aria-hidden='true'] > span", count: 2, visible: :all
    assert_selector "#{menu} button[data-admin--editor--section-layout-param='one_two'] .sr-only", text: "One third, two thirds", visible: :all
    assert_selector "#{menu} button[aria-current='false']", count: 5, visible: :all
    # The trigger shows the current layout: three equal columns.
    assert_selector "#{menu} button[aria-haspopup='menu'] .admin-layout-diagram > span", count: 3, visible: :all
  end

  test "the menu moves, duplicates, removes keeping the blocks, and deletes behind a dialog that counts them" do
    render_card

    assert_selector "button[data-move='up']", text: "Move up", visible: :all
    assert_selector "form[action$='/content_blocks/#{@section.id}/duplicate']", visible: :all
    assert_selector "form[action$='/content_blocks/#{@section.id}'] input[name='keep_blocks'][value='1']", visible: :all
    assert_selector "#section-#{@section.id}-delete-count", text: "This also deletes the 2 blocks in it.", visible: :all
  end

  test "the section's menu is named, its Move items follow the card's place, and Delete opens the section's own dialog" do
    outline = BlockOutline.new(@editor_page.content_blocks.reload)
    render_inline Admin::EditorScreen::SectionCardComponent.new(page: @editor_page, section: outline.top_level.first, outline: outline, locale: "en", first: true, last: false)

    header = ".admin-section-card > div:first-child"
    assert_selector "#{header} button[aria-haspopup='menu'][aria-label='Section actions']", text: "⋯"
    assert_selector "#{header} button[data-move='up'][disabled][data-action='click->admin--editor--blocks#moveUp']", visible: :all
    assert_selector "#{header} button[data-move='down']:not([disabled])[data-action='click->admin--editor--blocks#moveDown']", text: "Move down", visible: :all
    assert_selector "#{header} button[data-admin--ui--dialog-id-param='delete-section-#{@section.id}']", text: "Delete section and its blocks…", visible: :all
    assert_selector "dialog#delete-section-#{@section.id} form[action$='/content_blocks/#{@section.id}'] button[type=submit]", text: "Delete section", visible: :all
    assert_no_selector "dialog#delete-section-#{@section.id} input[name='keep_blocks']", visible: :all
    # No form inside the settings form: a nested form is dropped by the parser.
    assert_no_selector "form#section-#{@section.id}-form form", visible: :all
  end

  test "the delete dialog counts one block in the singular and says nothing of blocks for an empty section" do
    @image.destroy!
    render_card
    assert_selector "#section-#{@section.id}-delete-count", text: "This also deletes the 1 block in it.", exact_text: true, visible: :all

    @text.destroy!
    render_card
    assert_selector "p#section-#{@section.id}-delete-count", text: "", exact_text: true, visible: :all
  end

  # The line a delete or an add inside the section replaces
  # (`Admin::Answers::BlockDrawing#section_count_streams`).
  test "the delete count a stream replaces is the one the card draws" do
    render_card
    card = Capybara.string(rendered_content).find("#section-#{@section.id}-delete-count", visible: :all)

    alone = Capybara.string(render_inline(Admin::EditorScreen::SectionCardComponent.delete_count(section: @section, count: 2)).to_html).find("#section-#{@section.id}-delete-count", visible: :all)

    assert_equal [ card.text(:all), card[:class] ], [ alone.text(:all), alone[:class] ]
    assert_equal "section-#{@section.id}-delete-count", Admin::EditorScreen::SectionCardComponent.delete_count_id(@section)
  end

  test "a viewer who can't edit the page gets no form controls, no menu and no handle" do
    outline = BlockOutline.new(@editor_page.content_blocks.reload)
    render_inline Admin::EditorScreen::SectionCardComponent.new(page: @editor_page, section: outline.top_level.first, outline: outline, locale: "en", editable: false)

    assert_no_selector ".admin-block-card__handle"
    assert_no_selector "[aria-label='Section actions']"
    assert_selector "fieldset[disabled] select[name='block[settings][background]']", visible: :all
    assert_selector "fieldset[disabled] button[aria-haspopup='menu'][aria-label='Layout']", visible: :all
    assert_no_selector "form[data-controller~='admin--saving--autosave']"
    assert_no_selector "dialog#delete-section-#{@section.id}", visible: :all
  end

  # One string for a menu item's look, wherever a menu of the block list is drawn.
  test "the lane picker's and the section menu's items use the block card's menu item class" do
    assert_same Admin::EditorScreen::BlockCardComponent::MENU_ITEM_CLASS, Admin::EditorScreen::BlockPickerComponent::MENU_ITEM_CLASS
  end

  test "a tile is the block's element: its dom id, a button that names the panel it opens, collapsed" do
    render_card

    tile = "#section-#{@section.id}-lane-3 > ##{ActionView::RecordIdentifier.dom_id(@image)}[role='listitem'][data-block-id='#{@image.id}'][data-admin--editor--section-target='tile'][data-admin--editor--blocks-target='tile']"
    assert_selector tile
    assert_selector "#{tile} > button.admin-block-tile__face[type='button'][aria-expanded='false'][aria-controls='block-#{@image.id}-panel'][data-action='admin--editor--section#toggle']", text: "Image"
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
    outline = BlockOutline.new(@editor_page.content_blocks.reload)
    render_inline Admin::EditorScreen::SectionCardComponent.new(page: @editor_page, section: outline.top_level.first, outline: outline, locale: "en", editable: false)

    assert_no_selector ".admin-block-tile__grip", visible: :all
    assert_selector "##{ActionView::RecordIdentifier.dom_id(@image)} > button.admin-block-tile__face"
  end

  test "the panels are in reading order, column by column" do
    late = @editor_page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    render_card

    ids = page.all("#section-#{@section.id}-panels > [data-admin--editor--section-target='panel']", visible: :all).map { |panel| panel["data-block-id"].to_i }
    assert_equal [ @text.id, late.id, @image.id ], ids
  end

  test "one column and one block are counted in the singular" do
    @image.destroy!
    @section.update!(settings: { "layout" => "one" })
    render_card

    assert_selector "#section-#{@section.id}-summary", text: "1 block", exact_text: true
    assert_selector "#section-#{@section.id}-words button", text: "1 column"
    assert_selector "#section-#{@section.id}-lanes[data-columns='1'][style*='--lanes: 1']"
  end

  # One rule for the page view and for a card streamed in (`Admin
  # ::Answers::BlockDrawing#card_for`): a top-level block is drawn as a
  # section when it is a container, or holds blocks although its type is gone.
  test "a block is drawn as a section when it is a container or still holds blocks, and a plain block never" do
    outline = BlockOutline.new(@editor_page.content_blocks.reload)
    section = outline.top_level.first
    assert Admin::EditorScreen::SectionCardComponent.draws?(section, outline: outline)
    assert_not Admin::EditorScreen::SectionCardComponent.draws?(@text, outline: outline)

    @section.update_columns(block_type: "gone/section")
    outline = BlockOutline.new(@editor_page.content_blocks.reload)
    assert Admin::EditorScreen::SectionCardComponent.draws?(outline.top_level.first, outline: outline)

    [ @text, @image ].each(&:destroy!)
    outline = BlockOutline.new(@editor_page.content_blocks.reload)
    assert_not Admin::EditorScreen::SectionCardComponent.draws?(outline.top_level.first, outline: outline)
  end

  # ---- A section whose type is gone (sections spec §6) ----------------------

  test "a section whose type is gone is the Unavailable type card with its blocks listed under it" do
    @section.update_columns(block_type: "gone/section")
    as(users(:one), channel: :admin) { render_card }

    assert_selector ".admin-section-card[data-card-edge='unavailable'][data-container][data-admin--editor--blocks-target='card']", text: "Unavailable type — gone/section"
    assert_selector ".admin-section-card", text: "Its blocks are still here. Remove the section and keep them, move them out one by one, or delete it with them."
    assert_selector ".admin-block-tile", count: 2
    assert_selector "[data-admin--editor--blocks-target='lane'][data-no-drop]", count: 2
    assert_no_selector "[data-admin--editor--blocks-target='lane']:not([data-no-drop])", visible: :all
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
    assert_selector "#section-#{@section.id}-panels > [data-admin--editor--section-target='panel']", count: 2, visible: :all
  end

  # Its two actions are a section's two removals, under the menu's own words:
  # the one that keeps the blocks is a form of its own, sent with
  # `keep_blocks` and only on a settled screen (`admin--saving--queue-hold`: its
  # answer replaces the blocks' forms); the other opens the dialog.
  test "it has no handle, no menu and no settings; its two actions are Remove section, keep blocks and the dialog that counts its blocks" do
    @section.update_columns(block_type: "gone/section")
    as(users(:one), channel: :admin) { render_card }
    header = "##{ActionView::RecordIdentifier.dom_id(@section)} > div:first-child"

    assert_no_selector ".admin-block-card__handle", visible: :all
    assert_no_selector "button[aria-label='Section actions']", visible: :all
    assert_no_selector "select, [data-admin--editor--section-target='layoutMenu']", visible: :all
    assert_no_selector "#section-#{@section.id}-summary", visible: :all
    keep = "#{header} form[action$='/content_blocks/#{@section.id}'][data-controller='admin--saving--queue-hold'][data-action='submit->admin--saving--queue-hold#submit']"
    assert_selector "#{keep} input[name='_method'][value='delete']", visible: :all
    assert_selector "#{keep} input[name='keep_blocks'][value='1']", visible: :all
    assert_selector "#{keep} button[type='submit']", text: "Remove section, keep blocks", exact_text: true
    assert_selector "#{header} button[data-admin--ui--dialog-id-param='delete-section-#{@section.id}']", text: "Delete section and its blocks…", exact_text: true
    assert_selector "#{header} button", count: 2
    assert_selector "dialog#delete-section-#{@section.id} #section-#{@section.id}-delete-count", text: "This also deletes the 2 blocks in it.", visible: :all
    assert_selector "dialog#delete-section-#{@section.id} form[action$='/content_blocks/#{@section.id}'] input[name='_method'][value='delete']", visible: :all
    assert_no_selector "dialog input[name='keep_blocks']", visible: :all
    assert_selector "input[name='keep_blocks']", count: 1, visible: :all
  end

  test "a viewer who can't edit sees the unavailable section and its tiles, and nothing that deletes" do
    @section.update_columns(block_type: "gone/section")
    as(users(:reader), channel: :admin) { render_card }

    assert_selector ".admin-section-card[data-card-edge='unavailable']", text: "Unavailable type — gone/section"
    assert_selector ".admin-block-tile", count: 2
    assert_no_selector "button", text: "Remove section, keep blocks", visible: :all
    assert_no_selector "button", text: "Delete section and its blocks…", visible: :all
    assert_no_selector "input[name='keep_blocks']", visible: :all
    assert_no_selector "form[data-controller='admin--saving--queue-hold']", visible: :all
    assert_no_selector "dialog", visible: :all
    assert_no_selector ".admin-block-tile__grip", visible: :all
  end

  # ----- Held (live-editing Task 7) -----

  def render_card_for(viewer, tab)
    outline = BlockOutline.new(@editor_page.content_blocks.reload)
    as_viewer(viewer, tab: tab) { render_inline Admin::EditorScreen::SectionCardComponent.new(page: @editor_page, section: outline.top_level.first, outline: outline, locale: "en") }
  end

  def controls_of(selector) = form_controls(within: selector)

  test "the header carries the anchor field with its stored value, its help line and its own error slot" do
    @section.update!(settings: @section.settings.merge("anchor" => "services"))
    render_card

    assert_selector "#section-#{@section.id}-form input[type=text][name='block[settings][anchor]'][value=services][id='block-#{@section.id}-anchor'][autocomplete=off]:not([maxlength])", visible: :all
    assert_selector "#section-#{@section.id}-form input[name='block[settings][anchor]'][aria-label='Anchor'][aria-describedby='block-#{@section.id}-anchor-help']", visible: :all
    assert_selector "#block-#{@section.id}-anchor-help", text: "Lets a link jump here, as #anchor. Leave empty for none.", visible: :all
    assert_selector "#block-#{@section.id}-anchor-errors", visible: :all
  end

  test "a section whose anchor field is held by someone else keeps the anchor field read-only with its value" do
    @section.update!(settings: @section.settings.merge("anchor" => "services"))
    dana = users(:two)
    dana.update!(name: "Dana Weiss")
    reserve(@section, @editor_page, dana, "tab-bbbbbbbb")
    render_card_for(users(:one), "tab-aaaaaaaa")

    assert_selector "#section-#{@section.id}-form input[name='block[settings][anchor]'][value=services][readonly]", visible: :all
  end

  test "a section whose own settings are held by someone else: the strip in its slot, the form read-only with the same names and values, no autosave on it" do
    dana = users(:two)
    dana.update!(name: "Dana Weiss")
    render_card_for(users(:one), "tab-aaaaaaaa")
    editable = controls_of("#section-#{@section.id}-form")
    assert_selector "#section-#{@section.id}-form[data-controller~='admin--saving--autosave']", visible: :all

    reserve(@section, @editor_page, dana, "tab-bbbbbbbb")
    render_card_for(users(:one), "tab-aaaaaaaa")

    assert_selector "#block-#{@section.id}-hold[data-editing-strip-slot] [data-editing-kind=held]", text: "Dana Weiss is editing this block", visible: :all
    assert_selector "#section-#{@section.id}-form[data-editing-unit][data-editing-held=true]:not([data-controller])", visible: :all
    assert_equal editable, controls_of("#section-#{@section.id}-form")
    assert_selector "#section-#{@section.id}-form select[disabled]", count: 2, visible: :all
    assert_selector "[role=menu] button[data-action='admin--editing--hold#takeOver']", text: "Take over", visible: :all
  end

  test "held by nobody the slot is there and empty, and held by the viewer in this tab it is drawn as ever" do
    render_card_for(users(:one), "tab-aaaaaaaa")
    assert_selector "#block-#{@section.id}-hold[data-editing-strip-slot]:empty", visible: :all

    reserve(@section, @editor_page, users(:one), "tab-aaaaaaaa")
    render_card_for(users(:one), "tab-aaaaaaaa")
    assert_selector "#section-#{@section.id}-form[data-controller~='admin--saving--autosave']", visible: :all
    assert_no_selector "[data-editing-held]"
  end

  test "a held block in a section: its panel is read-only with the strip and its tile says held, while the section stays editable" do
    dana = users(:two)
    reserve(@text, @editor_page, dana, "tab-bbbbbbbb")

    render_card_for(users(:one), "tab-aaaaaaaa")

    assert_selector "#block-#{@text.id}-panel[hidden][data-editing-held=true] fieldset.admin-held", visible: :all
    assert_selector "#block-#{@text.id}-panel #block-#{@text.id}-hold [data-editing-kind=held]", visible: :all
    assert_no_selector "#block-#{@text.id}-panel [data-controller~='admin--saving--autosave']", visible: :all
    assert_selector "#content_block_#{@text.id}.admin-block-tile[data-editing-held=true]", visible: :all
    assert_selector "#section-#{@section.id}-form[data-controller~='admin--saving--autosave']", visible: :all
    assert_selector "#block-#{@image.id}-panel form[data-controller~='admin--saving--autosave']", visible: :all
  end
end
