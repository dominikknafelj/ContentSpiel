require "test_helper"

# A section on a translation tab (sections spec §4.5): a heading row over its
# blocks' cards in reading order, each with its pair of fields. Nothing of
# the lanes -- no tile, no panel, no handle -- because structure is edited on
# the default language's tab; its settings are the head's words and a region
# that shows them read only (Design System v124).
class Admin::EditorScreen::SectionGroupComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    with_locales(%w[en de], default: "en")
    # `@owner`, not `@page`: ViewComponent's test helpers keep the rendered
    # page in `@page`, and two of these tests render twice.
    @owner = create_page(title: "Section group")
    @section = @owner.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "three" })
    @text = @owner.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 0, body: rich_doc("Hello from a column"))
    @image = @owner.content_blocks.create!(block_type: "image", section: @section, section_column: 3, position: 0, alt: "A harbour at dawn")
    @late = @owner.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
  end

  def group_for(locale: "de", editable: nil)
    outline = BlockOutline.new(@owner.content_blocks.reload)
    Admin::EditorScreen::SectionCardComponent.for(page: @owner, section: outline.top_level.first, outline: outline, locale: locale, first: true, last: true, editable: editable)
  end

  def render_group(**options) = render_inline(group_for(**options))

  def group = "##{ActionView::RecordIdentifier.dom_id(@section)}.admin-section-group"

  def head = "#{group} > .admin-section-group__head"

  test "it is one group under the heading Section, with a card per block in reading order" do
    render_group

    assert_selector ".admin-section-group", count: 1
    assert_selector "#{group}[data-block-id='#{@section.id}'][data-container][data-admin--editor--blocks-target='card'] > .admin-section-group__head > h3", text: "Section", exact_text: true
    cards = page.all("#{group} > .admin-block-card").map { |card| card["data-block-id"].to_i }
    assert_equal [ @text.id, @late.id, @image.id ], cards
  end

  test "nothing of the lanes is in it: no tile, no panel, no handle, no menu but each card's Add note, and no card of its own to move" do
    as(users(:one), channel: :admin) { render_group }

    assert_no_selector ".admin-block-tile", visible: :all
    assert_no_selector "[data-admin--editor--section-target~='tile'], [data-admin--editor--section-target~='panel'], [data-admin--editor--section-target~='lanes']", visible: :all
    assert_no_selector ".admin-block-card__handle", visible: :all
    assert_no_selector "button[aria-label='Section actions']", visible: :all
    # Each block's card has the "⋯" with "Add note" as its only item (the
    # notes handoff's decision 6), and nothing of the list's menu.
    assert_selector "button[aria-label='Block actions']", count: 3
    assert_equal [ "Add note" ] * 3, page.all(".admin-block-card > div:first-child [role=menu] > div", visible: :all).map { |item| item.text(:all).strip }
    assert_no_selector "[data-move]", visible: :all
    assert_no_selector "[data-admin--editor--blocks-target='lane']", visible: :all
    assert_selector "[data-admin--editor--blocks-target='card']", count: 1
    # Hidden directly in the group: the region's home and the closed region alone.
    assert_equal [ "span", "section-#{@section.id}-settings" ], page.all(".admin-section-group > [hidden]", visible: :all).map { |node| node[:id] || node.tag_name }
  end

  test "its heading row says the settings in the card head's words, each opening the read-only region" do
    @section.update!(settings: { "layout" => "three", "anchor" => "about" })
    render_group

    assert_selector "#{group}[data-controller='admin--editor--section'][data-admin--editor--section-settings-id-value='section-#{@section.id}-settings']"
    # Escape is the heading row's: on the group it would reach a block card's
    # Escape and hide a gone card holding unsaved text.
    assert_selector "#{head}[data-action='keydown.esc->admin--editor--section#escape']"
    assert_not_includes page.find(group)["data-action"].to_s, "keydown"
    words = page.all("#{head} #section-#{@section.id}-words[data-admin--editor--section-target='words'] button", visible: :all)
    assert_equal [ "3 columns ▾", "No background ▾", "Content width ▾", "#about ▾" ], words.map { |word| word.text(:all).squish }
    assert_equal %w[layout background width anchor], words.map { |word| word["data-admin--editor--section-field-param"] }
    words.each { |word| assert_equal "section-#{@section.id}-settings", word["aria-controls"] }
  end

  test "its settings region shows the words as rows under the form's labels, the same in every language, with a link to the default language" do
    @section.update!(settings: { "layout" => "three", "anchor" => "about" })
    render_group

    region = "#{group} > [data-section-settings-home] + #section-#{@section.id}-settings[hidden][data-controller='admin--editor--section-settings'][data-section-id='#{@section.id}']"
    assert_selector region, visible: :all
    # Named by the heading and the section's own words, so two sections' regions differ.
    assert_selector "#{region}[role=region][aria-labelledby='section-#{@section.id}-heading section-#{@section.id}-words']", visible: :all
    assert_selector "#{head} > #section-#{@section.id}-words", visible: :all
    assert_selector "#{head} > h3#section-#{@section.id}-heading", text: "Section"
    rows = page.all("#{region} dl > div[tabindex='-1'][data-section-setting]", visible: :all)
    assert_equal %w[layout background width anchor], rows.map { |row| row["data-section-setting"] }
    assert_equal [ [ "Layout", "3 columns" ], [ "Background", "No background" ], [ "Width", "Content width" ], [ "Anchor", "#about" ] ],
      rows.map { |row| [ row.find("dt", visible: :all).text(:all), row.find("dd", visible: :all).text(:all) ] }
    assert_selector "#{region} p.text-xs.text-meta", text: "Same in every language", visible: :all
    assert_selector "#{region} a[href='/cs-studio/pages/#{@owner.id}?section=#{@section.id}']", text: "Edit in English", visible: :all
  end

  # A translation tab never sends a shared value, and the region is moved
  # into the rail: nothing in it may be a second copy of the default tab's
  # form that could be submitted.
  test "its settings region holds no form and no control" do
    as(users(:one), channel: :admin) { render_group }

    region = "#section-#{@section.id}-settings"
    %w[form input select textarea button fieldset].each { |tag| assert_no_selector "#{region} #{tag}", visible: :all }
    assert_no_selector "#{region} [name]", visible: :all
    assert_no_selector "#section-#{@section.id}-form", visible: :all
  end

  test "Style and Anchor rows show only when the head says them" do
    render_group

    assert_equal %w[layout background width], page.all("#section-#{@section.id}-settings [data-section-setting]", visible: :all).map { |row| row["data-section-setting"] }
  end

  test "each block's translated field is a pair with its original, in an autosave form" do
    as(users(:one), channel: :admin) { render_group }

    assert_selector "##{ActionView::RecordIdentifier.dom_id(@image)} .admin-translation-pair", text: "A harbour at dawn"
    assert_selector "##{ActionView::RecordIdentifier.dom_id(@image)} .admin-translation-pair #block-#{@image.id}-alt"
    assert_selector "##{ActionView::RecordIdentifier.dom_id(@text)} .admin-translation-pair", text: "Hello from a column"
    assert_selector "#{group} form[data-controller~='admin--saving--autosave']", count: 3
  end

  # A block card of the list carries its "Delete this block?" dialog; in the
  # group nothing opens one, so none is drawn.
  test "a card of the group has no delete dialog, since nothing in it opens one" do
    as(users(:one), channel: :admin) { render_group }

    assert_no_selector "dialog", visible: :all
  end

  test "view only stays view only: disabled fields, no autosave" do
    as(users(:reader), channel: :admin) { render_group }

    assert_selector "#{group} > .admin-block-card", count: 3
    assert_selector "#{group} fieldset[disabled]", count: 3
    assert_no_selector "form[data-controller~='admin--saving--autosave']", visible: :all
    assert_no_selector "dialog", visible: :all
  end

  # Spec §6: a block of a removed type keeps its one action wherever it is
  # drawn. In the group there is no tile to hold its dialog, so the card does.
  test "a block of a type that is gone is the Unavailable card, with Delete block… for an editor only" do
    @late.update_columns(block_type: "gone/thing")

    as(users(:one), channel: :admin) { render_group }
    assert_selector "##{ActionView::RecordIdentifier.dom_id(@late)}[data-card-edge='unavailable']", text: "Unavailable type — gone/thing"
    assert_selector "##{ActionView::RecordIdentifier.dom_id(@late)} button[data-admin--ui--dialog-id-param='delete-block-#{@late.id}']", text: "Delete block…"
    assert_selector "dialog#delete-block-#{@late.id}", count: 1, visible: :all

    as(users(:reader), channel: :admin) { render_group }
    assert_no_selector "button", text: "Delete block…", visible: :all
    assert_no_selector "dialog", visible: :all
  end

  # A section whose type is gone still holds its blocks (spec §6), and they
  # still have their translations: the group says what it is and lists them.
  test "a section whose type is gone is a group named Unavailable type, with its blocks" do
    @section.update_columns(block_type: "gone/section")
    render_group

    assert_selector "#{head} > h3.text-danger-ink", text: "Unavailable type — gone/section", exact_text: true
    assert_selector "#{group} > .admin-block-card", count: 3
    # No words, no region: a section whose type is gone is never chosen.
    assert_no_selector "#section-#{@section.id}-words, #section-#{@section.id}-settings", visible: :all
    assert_no_selector "#{group}[data-controller]"
  end

  test "an empty section is the heading row and its settings alone" do
    [ @text, @image, @late ].each(&:destroy!)
    render_group

    assert_equal [ "section-#{@section.id}-header", "span", "section-#{@section.id}-settings" ], page.all("#{group} > *", visible: :all).map { |node| node[:id].presence || node.tag_name }
  end

  test ".for is the group on a translation tab and the card on the default language's" do
    assert_kind_of Admin::EditorScreen::SectionGroupComponent, group_for(locale: "de")
    assert_kind_of Admin::EditorScreen::SectionCardComponent, group_for(locale: "en")
    assert_kind_of Admin::EditorScreen::SectionCardComponent, group_for(locale: :en)
  end

  # "Suggest translations for N empty fields" walks every block of the page
  # (`Admin::TranslationScreen::TranslateAllComponent`), so a block in a
  # column counts as one outside a section does: the text's body and the
  # image's alt here.
  test "the blocks in a column are among the fields Suggest translations counts" do
    count = ->(record) { Admin::TranslationScreen::TranslateAllComponent.new(record: record.reload, locale: "de", editable: true).count }

    assert_equal count.call(create_page(title: "No blocks")) + 2, count.call(@owner)
  end
end
