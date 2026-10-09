require "test_helper"

class Admin::BlockCardComponentTest < ViewComponent::TestCase
  include ContentHelper
  include TestTypes

  test "renders the type label, schema fields and error slots for a registered type" do
    page = create_page(title: "Card test")
    block = page.content_blocks.create!(block_type: "post_list", position: 0, settings: { "limit" => 3 })

    render_inline Admin::BlockCardComponent.new(page: page, block: block, locale: "en")

    assert_text "Post list"
    assert_selector "input[name='block[settings][limit]'][value='3']"
    assert_selector "##{Admin::BlockCardComponent.error_prefix(block)}-limit-errors"
    assert_selector "form[action$='/content_blocks/#{block.id}'][data-controller~='admin--autosave']"
  end

  def render_card(block, page:, **options)
    render_inline Admin::BlockCardComponent.new(page: page, block: block, locale: "en", **options)
  end

  test "the header has a drag handle, the type name as a collapse button and a Block actions menu" do
    page = create_page(title: "Header test")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page)

    assert_selector ".admin-block-card__handle[aria-label='Move Rich text']"
    assert_selector "button[aria-expanded='true'][data-action$='admin--blocks#toggle']", text: "Rich text"
    assert_selector "button[aria-haspopup='menu'][aria-label='Block actions']", text: "⋯"
    assert_no_selector "summary", visible: :all
  end

  test "the menu lists Move up, Move down, Duplicate, a divider, then Delete block…, in that order" do
    page = create_page(title: "Menu test")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page)

    items = Capybara.string(rendered_content).all(".admin-block-card > div:first-child [role=menu] [role=none]", visible: :all)
    assert_equal [ "Move up", "Move down", "Duplicate", "", "Delete block…" ], items.map { |item| item.text(:all).strip }
    assert_selector "[role=menu] [role=separator]", visible: :all
    assert_selector "[role=menu] button.text-danger-ink", text: "Delete block…", visible: :all
    assert_selector "[role=menu] form[action$='/duplicate']", visible: :all
  end

  test "Move up is disabled on the first card, Move down on the last, both on a lone card" do
    page = create_page(title: "Disabled test")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page, first: true)
    assert_selector "button[data-move='up'][disabled]", visible: :all
    assert_no_selector "button[data-move='down'][disabled]", visible: :all

    render_card(block, page: page, last: true)
    assert_selector "button[data-move='down'][disabled]", visible: :all
    assert_no_selector "button[data-move='up'][disabled]", visible: :all

    render_card(block, page: page)
    assert_no_selector "button[data-move][disabled]", visible: :all
  end

  test "the menu's Move buttons keep calling admin--blocks#moveUp and #moveDown" do
    page = create_page(title: "Actions test")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page)

    assert_selector "button[data-move='up'][data-action~='click->admin--blocks#moveUp']", visible: :all
    assert_selector "button[data-move='down'][data-action~='click->admin--blocks#moveDown']", visible: :all
  end

  test "Delete block… opens a destructive confirm that says blocks skip the trash" do
    page = create_page(title: "Confirm test")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page)

    assert_selector "[role=menu] button[data-admin--dialog-id-param='delete-block-#{block.id}']", text: "Delete block…", visible: :all
    assert_selector "dialog#delete-block-#{block.id}", visible: :all
    assert_text "Delete this block?", normalize_ws: true
    assert_text "Blocks don’t go to the trash. This can’t be undone.", normalize_ws: true
    assert_selector "dialog form[method='post'] button", text: "Delete block", visible: :all
  end

  test "a post list's Type, Tag and Limit share one row, with a single-value tag chip input and one help line" do
    page = create_page(title: "Post list test")
    block = page.content_blocks.create!(block_type: "post_list", position: 0, settings: { "limit" => 3, "tag" => "news" })
    prefix = Admin::BlockCardComponent.error_prefix(block)

    render_card(block, page: page)

    assert_selector ".admin-block-settings-row select[name='block[settings][content_type]']"
    assert_selector ".admin-block-settings-row [data-controller='admin--chip-input'][data-admin--chip-input-single-value='true'][data-admin--chip-input-create-value='false']"
    assert_selector ".admin-block-settings-row input[type=hidden][name='block[settings][tag]'][value='news']", visible: :all
    assert_selector ".admin-block-settings-row [data-admin--chip-input-search-url-value$='/tags/suggest']"
    assert_selector ".admin-block-settings-row input[type=number][name='block[settings][limit]'][value='3']"
    assert_selector "##{prefix}-limit-errors", visible: :all
    assert_selector "##{prefix}-tag-errors", visible: :all
    assert_text "Shows the newest posts of this type.", count: 1
  end

  test "an unavailable type is a danger-bordered card with its sentence, Delete block… only, and no form" do
    page = create_page(title: "Unavailable test")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    block.update_column(:block_type, "gone/thing")

    render_card(block.reload, page: page)

    assert_selector ".admin-block-card.border-danger"
    assert_text "Unavailable type — gone/thing"
    assert_text "Its content is kept but can’t be shown or edited."
    assert_selector "button", text: "Delete block…"
    assert_no_selector "[role=menu]", visible: :all
    assert_no_selector ".admin-block-card__handle", visible: :all
    assert_no_selector "form[data-controller~='admin--autosave']"
    assert_no_selector "[data-block-body], input[name^='block['], textarea, select", visible: :all
    refute_text "Duplicate"
    refute_text "Move up"
  end

  # Task 12's b5: a viewer who can't edit the page sees an unavailable card
  # with no action at all, and a post list with every field disabled.
  test "a view-only unavailable card has no Delete, no handle and no menu; a view-only post list's fields are disabled" do
    page = create_page(title: "View only")
    gone = page.content_blocks.create!(block_type: "rich_text", position: 0)
    gone.update_column(:block_type, "gone/thing")
    render_card(gone.reload, page: page, editable: false)
    assert_text "Unavailable type — gone/thing"
    assert_no_selector "button", text: "Delete block…"
    assert_no_selector ".admin-block-card__handle, [role=menu]", visible: :all

    list = page.content_blocks.create!(block_type: "post_list", position: 1, settings: { "limit" => 3, "tag" => "news" })
    render_card(list, page: page, editable: false)
    assert_selector "fieldset[disabled].admin-view-only .admin-block-settings-row"
    assert_no_selector ".admin-block-card__handle, [role=menu]", visible: :all
    assert_no_selector "form[data-controller~='admin--autosave']"
  end

  test "an image block's alt and caption are per-use overrides with the library text as placeholder and Reset" do
    page = create_page(title: "Image test")
    asset = create_media_asset
    asset.update!(alt: "A dog", caption: "Our dog")
    block = page.content_blocks.create!(block_type: "image", position: 0, media_asset: asset, alt: "Mine")
    prefix = Admin::BlockCardComponent.error_prefix(block)

    render_card(block, page: page)

    assert_selector "input##{prefix}-alt[name='block[alt]'][placeholder='A dog'][value='Mine']"
    assert_selector "input##{prefix}-caption[name='block[caption]'][placeholder='Our dog']"
    assert_selector "[data-admin--override-field-input-id-value='#{prefix}-alt']"
    assert_selector "[data-admin--override-field-input-id-value='#{prefix}-caption']"
    assert_text "Empty uses the alt text from Media"
    assert_text "Empty uses the caption from Media"
  end

  test "translated schema fields show the default-locale original in another locale" do
    with_test_types do
      page = create_page(title: "Translated field test")
      block = page.content_blocks.create!(block_type: "test/quote", position: 0, translated_settings: { "en" => { "text" => "Hello" } })

      render_inline Admin::BlockCardComponent.new(page: page, block: block, locale: "de")

      assert_selector "[data-original-for='text']", text: "Hello"
    end
  end

  test "two cards of the same block type never compute the same field id" do
    page = create_page(title: "Id collision test")
    first = page.content_blocks.create!(block_type: "post_list", position: 0)
    second = page.content_blocks.create!(block_type: "post_list", position: 1)

    assert_not_equal Admin::BlockCardComponent.error_prefix(first), Admin::BlockCardComponent.error_prefix(second)
  end

  test "as a panel it is the block's own form with a heading naming its column, hidden, and no card chrome" do
    page = create_page(title: "Panel")
    section = page.content_blocks.create!(block_type: "section", position: 0)
    block = page.content_blocks.create!(block_type: "image", section: section, section_column: 2, position: 0)

    render_inline Admin::BlockCardComponent.new(page: page, block: block, locale: "en", placement: :panel)

    assert_selector "#block-#{block.id}-panel[hidden][data-admin--section-target='panel'][data-block-id='#{block.id}']", visible: :all
    assert_selector "#block-#{block.id}-panel-title", text: "Image · column 2", visible: :all
    assert_selector "form[action$='/content_blocks/#{block.id}'][data-controller~='admin--autosave']", visible: :all
    assert_selector "#block-#{block.id}-save-status", visible: :all
    assert_no_selector ".admin-block-card__handle", visible: :all
    assert_no_selector "[data-admin--blocks-target='card']", visible: :all
    assert_selector "button[data-action='admin--section#close']", visible: :all
  end

  test "as a list card it is exactly what it was" do
    page = create_page(title: "List")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page)

    assert_selector "##{ActionView::RecordIdentifier.dom_id(block)}[data-admin--blocks-target='card']"
    assert_no_selector "[data-admin--section-target]"
  end

  # The panel has the block's `dom_id` nowhere: in a section that id is the
  # tile's, and two elements with it would make a stream's target ambiguous.
  test "a panel has no menu, no collapse button and not the block's dom id, and is a region named by its heading" do
    page = create_page(title: "Panel chrome")
    section = page.content_blocks.create!(block_type: "section", position: 0)
    block = page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)

    render_inline Admin::BlockCardComponent.new(page: page, block: block, locale: "en", placement: :panel)

    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(block)}", visible: :all
    assert_no_selector "button[aria-label='Block actions']", visible: :all
    assert_no_selector "[data-action$='admin--blocks#toggle']", visible: :all
    assert_selector "#block-#{block.id}-panel[role='region'][aria-labelledby='block-#{block.id}-panel-title']", visible: :all
  end

  test "an unavailable block's panel says so and can still be closed" do
    page = create_page(title: "Unavailable panel")
    section = page.content_blocks.create!(block_type: "section", position: 0)
    block = page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    block.update_column(:block_type, "gone/thing")

    render_inline Admin::BlockCardComponent.new(page: page, block: block.reload, locale: "en", placement: :panel)

    assert_selector "#block-#{block.id}-panel", text: "Unavailable type — gone/thing", visible: :all
    assert_selector "button[data-action='admin--section#close']", visible: :all
    assert_no_selector "form[data-controller~='admin--autosave']", visible: :all
  end

  test "as a group card it has the type's name and neither handle, menu nor targets" do
    page = create_page(title: "Group")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page, placement: :group)

    assert_selector "##{ActionView::RecordIdentifier.dom_id(block)}", text: "Rich text"
    assert_selector "form[data-controller~='admin--autosave']"
    assert_no_selector ".admin-block-card__handle"
    assert_no_selector "button[aria-label='Block actions']"
    assert_no_selector "[data-admin--blocks-target], [data-admin--section-target]"
  end

  test "an unknown placement is refused" do
    page = create_page(title: "Placement")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    assert_raises(ArgumentError) { Admin::BlockCardComponent.new(page: page, block: block, locale: "en", placement: :tile) }
  end
end
