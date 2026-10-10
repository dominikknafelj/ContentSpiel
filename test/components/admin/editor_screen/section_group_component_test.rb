require "test_helper"

# A section on a translation tab (sections spec §4.5): a heading over its
# blocks' cards in reading order, each with its pair of fields. Nothing of
# the lanes -- no tile, no panel, no handle -- because structure is edited on
# the default language's tab.
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

  test "it is one group under the heading Section, with a card per block in reading order" do
    render_group

    assert_selector ".admin-section-group", count: 1
    assert_selector "#{group}[data-block-id='#{@section.id}'][data-container][data-admin--editor--blocks-target='card'] > h3", text: "Section", exact_text: true
    cards = page.all("#{group} > .admin-block-card").map { |card| card["data-block-id"].to_i }
    assert_equal [ @text.id, @late.id, @image.id ], cards
  end

  test "nothing of the lanes is in it: no tile, no panel, no handle, no menu but each card's Add note, and no card of its own to move" do
    as(users(:one), channel: :admin) { render_group }

    assert_no_selector ".admin-block-tile", visible: :all
    assert_no_selector "[data-admin--editor--section-target]", visible: :all
    assert_no_selector ".admin-block-card__handle", visible: :all
    assert_no_selector "button[aria-label='Section actions']", visible: :all
    # Each block's card has the "⋯" with "Add note" as its only item (the
    # notes handoff's decision 6), and nothing of the list's menu.
    assert_selector "button[aria-label='Block actions']", count: 3
    assert_equal [ "Add note" ] * 3, page.all(".admin-block-card > div:first-child [role=menu] > div", visible: :all).map { |item| item.text(:all).strip }
    assert_no_selector "[data-move]", visible: :all
    assert_no_selector "[data-admin--editor--blocks-target='lane']", visible: :all
    assert_selector "[data-admin--editor--blocks-target='card']", count: 1
    assert_no_selector ".admin-section-group > [hidden]", visible: :all
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
    assert_selector "##{ActionView::RecordIdentifier.dom_id(@late)}.border-danger", text: "Unavailable type — gone/thing"
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

    assert_selector "#{group} > h3.text-danger-ink", text: "Unavailable type — gone/section", exact_text: true
    assert_selector "#{group} > .admin-block-card", count: 3
  end

  test "an empty section is the heading alone" do
    [ @text, @image, @late ].each(&:destroy!)
    render_group

    assert_selector "#{group} > *", count: 1
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
