require "test_helper"

class Admin::EditorScreen::BlockCardComponentTest < ViewComponent::TestCase
  include ContentHelper
  include TestTypes

  # The items of the card's own "⋯" menu, in its header (a rich-text field
  # has an Insert menu further down).
  def page_menu_items = page.all(".admin-block-card > div:first-child [role=menu] > div", visible: :all).map { |item| item.text(:all).strip }

  test "renders the type label, schema fields and error slots for a registered type" do
    page = create_page(title: "Card test")
    block = page.content_blocks.create!(block_type: "post_list", position: 0, settings: { "limit" => 3 })

    render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en")

    assert_text "Post list"
    assert_selector "input[name='block[settings][limit]'][value='3']"
    assert_selector "##{Admin::EditorScreen::BlockCardComponent.error_prefix(block)}-limit-errors"
    assert_selector "form[action$='/content_blocks/#{block.id}'][data-controller~='admin--saving--autosave']"
  end

  def render_card(block, page:, **options)
    render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", **options)
  end

  test "the header has a drag handle, the type name as a collapse button and a Block actions menu" do
    page = create_page(title: "Header test")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page)

    assert_selector ".admin-block-card__handle[aria-label='Move Rich text']"
    assert_selector "button[aria-expanded='true'][data-action$='admin--editor--blocks#toggle']", text: "Rich text"
    assert_selector "button[aria-haspopup='menu'][aria-label='Block actions']", text: "⋯"
    assert_no_selector "summary", visible: :all
  end

  test "the menu lists Move up, Move down, Move into section…, Duplicate, a divider, then Delete block…, in that order" do
    page = create_page(title: "Menu test")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page)

    items = Capybara.string(rendered_content).all(".admin-block-card > div:first-child [role=menu] [role=none]", visible: :all)
    assert_equal [ "Add note", "Move up", "Move down", "Move into section…", "Duplicate", "", "Delete block…" ], items.map { |item| item.text(:all).strip }
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
    assert_no_selector "button[data-move='up'][disabled], button[data-move='down'][disabled]", visible: :all
  end

  # Sections spec §4.4. Disabled as rendered: whether the page has a section
  # is the screen's to say (`admin--editor--blocks#refreshMoveState`), since sections
  # come and go without this card being drawn again.
  test "Move into section… fills the Move dialog and then opens it, and starts disabled" do
    page = create_page(title: "Into test")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page)

    assert_selector "[role=menu] button[disabled][data-move='into'][data-action='click->admin--editor--blocks#askWhere admin--ui--dialog#open'][data-admin--ui--dialog-id-param='move-block-dialog']",
      text: "Move into section…", visible: :all
  end

  # A section never holds a section: on a translation tab a section is drawn
  # by this component (`SectionCardComponent.draws?`), and is not offered it.
  test "a section's own card is not offered Move into section…" do
    page = create_page(title: "Section as a card")
    section = page.content_blocks.create!(block_type: "section", position: 0)

    render_card(section, page: page)

    assert_selector "[role=menu] button[data-move='up']", visible: :all
    assert_no_selector "button[data-move='into']", visible: :all
  end

  # The form of a block in a column is hidden until its tile is pressed, and
  # a dialog inside a hidden element can't be shown: the dialog is the
  # tile's (`Admin::EditorScreen::BlockTileComponent`), and a second one here
  # would be a second element with its id.
  test "a panel does not hold the block's delete dialog" do
    page = create_page(title: "Panel dialog")
    section = page.content_blocks.create!(block_type: "section", position: 0)
    block = page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)

    render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", placement: :panel)

    assert_selector "#block-#{block.id}-panel form[data-controller~='admin--saving--autosave']", visible: :all
    assert_no_selector "dialog", visible: :all
  end

  test "the menu's Move buttons keep calling admin--editor--blocks#moveUp and #moveDown" do
    page = create_page(title: "Actions test")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page)

    assert_selector "button[data-move='up'][data-action~='click->admin--editor--blocks#moveUp']", visible: :all
    assert_selector "button[data-move='down'][data-action~='click->admin--editor--blocks#moveDown']", visible: :all
  end

  test "Delete block… opens a destructive confirm that says blocks skip the trash" do
    page = create_page(title: "Confirm test")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page)

    assert_selector "[role=menu] button[data-admin--ui--dialog-id-param='delete-block-#{block.id}']", text: "Delete block…", visible: :all
    assert_selector "dialog#delete-block-#{block.id}", visible: :all
    assert_text "Delete this block?", normalize_ws: true
    assert_text "Blocks don’t go to the trash. This can’t be undone.", normalize_ws: true
    assert_selector "dialog form[method='post'] button", text: "Delete block", visible: :all
  end

  test "a post list's Type, Tag and Limit share one row, with a single-value tag chip input and one help line" do
    page = create_page(title: "Post list test")
    block = page.content_blocks.create!(block_type: "post_list", position: 0, settings: { "limit" => 3, "tag" => "news" })
    prefix = Admin::EditorScreen::BlockCardComponent.error_prefix(block)

    render_card(block, page: page)

    assert_selector ".admin-block-settings-row select[name='block[settings][content_type]']"
    assert_selector ".admin-block-settings-row [data-controller='admin--ui--chip-input'][data-admin--ui--chip-input-single-value='true'][data-admin--ui--chip-input-create-value='false']"
    assert_selector ".admin-block-settings-row input[type=hidden][name='block[settings][tag]'][value='news']", visible: :all
    assert_selector ".admin-block-settings-row [data-admin--ui--chip-input-search-url-value$='/tags/suggest']"
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
    assert_no_selector "form[data-controller~='admin--saving--autosave']"
    assert_no_selector "[data-block-body], input[name^='block['], textarea, select", visible: :all
    refute_text "Duplicate"
    refute_text "Move up"
  end

  # Task 12's b5: a viewer who can't edit the page sees an unavailable card
  # with no action at all, and a post list with every field disabled.
  test "a view-only unavailable card has no Delete, no handle and no menu; a view-only post list's fields are disabled and its menu is Add note alone" do
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
    # Its menu holds "Add note" and nothing of an editor's (the handoff's decision 6).
    assert_no_selector ".admin-block-card__handle, [data-move], form[action$='/duplicate'], dialog", visible: :all
    assert_equal [ "Add note" ], page_menu_items
    assert_no_selector "form[data-controller~='admin--saving--autosave']"
  end

  test "an image block's alt and caption are per-use overrides with the library text as placeholder and Reset" do
    page = create_page(title: "Image test")
    asset = create_media_asset
    asset.update!(alt: "A dog", caption: "Our dog")
    block = page.content_blocks.create!(block_type: "image", position: 0, media_asset: asset, alt: "Mine")
    prefix = Admin::EditorScreen::BlockCardComponent.error_prefix(block)

    render_card(block, page: page)

    assert_selector "input##{prefix}-alt[name='block[alt]'][placeholder='A dog'][value='Mine']"
    assert_selector "input##{prefix}-caption[name='block[caption]'][placeholder='Our dog']"
    assert_selector "[data-admin--ui--override-field-input-id-value='#{prefix}-alt']"
    assert_selector "[data-admin--ui--override-field-input-id-value='#{prefix}-caption']"
    assert_text "Empty uses the alt text from Media"
    assert_text "Empty uses the caption from Media"
  end

  test "translated schema fields show the default-locale original in another locale" do
    with_test_types do
      page = create_page(title: "Translated field test")
      block = page.content_blocks.create!(block_type: "test/quote", position: 0, translated_settings: { "en" => { "text" => "Hello" } })

      render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "de")

      assert_selector "[data-original-for='text']", text: "Hello"
    end
  end

  test "two cards of the same block type never compute the same field id" do
    page = create_page(title: "Id collision test")
    first = page.content_blocks.create!(block_type: "post_list", position: 0)
    second = page.content_blocks.create!(block_type: "post_list", position: 1)

    assert_not_equal Admin::EditorScreen::BlockCardComponent.error_prefix(first), Admin::EditorScreen::BlockCardComponent.error_prefix(second)
  end

  test "as a panel it is the block's own form with a heading naming its column, hidden, and no card chrome" do
    page = create_page(title: "Panel")
    section = page.content_blocks.create!(block_type: "section", position: 0)
    block = page.content_blocks.create!(block_type: "image", section: section, section_column: 2, position: 0)

    render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", placement: :panel)

    assert_selector "#block-#{block.id}-panel[hidden][data-admin--editor--section-target='panel'][data-block-id='#{block.id}']", visible: :all
    assert_selector "#block-#{block.id}-panel-title", text: "Image · column 2", visible: :all
    assert_selector "form[action$='/content_blocks/#{block.id}'][data-controller~='admin--saving--autosave']", visible: :all
    assert_selector "#block-#{block.id}-save-status", visible: :all
    assert_no_selector ".admin-block-card__handle", visible: :all
    assert_no_selector "[data-admin--editor--blocks-target='card']", visible: :all
    assert_selector "button[data-action='admin--editor--section#close']", visible: :all
  end

  test "as a list card it is exactly what it was" do
    page = create_page(title: "List")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page)

    assert_selector "##{ActionView::RecordIdentifier.dom_id(block)}[data-admin--editor--blocks-target='card']"
    assert_no_selector "[data-admin--editor--section-target]"
  end

  # The panel has the block's `dom_id` nowhere: in a section that id is the
  # tile's, and two elements with it would make a stream's target ambiguous.
  test "a panel has no menu, no collapse button and not the block's dom id, and is a region named by its heading" do
    page = create_page(title: "Panel chrome")
    section = page.content_blocks.create!(block_type: "section", position: 0)
    block = page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)

    render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", placement: :panel)

    assert_no_selector "##{ActionView::RecordIdentifier.dom_id(block)}", visible: :all
    assert_no_selector "button[aria-label='Block actions']", visible: :all
    assert_no_selector "[data-action$='admin--editor--blocks#toggle']", visible: :all
    assert_selector "#block-#{block.id}-panel[role='region'][aria-labelledby='block-#{block.id}-panel-title']", visible: :all
  end

  test "an unavailable block's panel says so and can still be closed" do
    page = create_page(title: "Unavailable panel")
    section = page.content_blocks.create!(block_type: "section", position: 0)
    block = page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
    block.update_column(:block_type, "gone/thing")

    render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block.reload, locale: "en", placement: :panel)

    assert_selector "#block-#{block.id}-panel", text: "Unavailable type — gone/thing", visible: :all
    assert_selector "button[data-action='admin--editor--section#close']", visible: :all
    assert_no_selector "form[data-controller~='admin--saving--autosave']", visible: :all
  end

  test "as a group card it has the type's name, a menu with Add note alone, and neither handle nor targets" do
    page = create_page(title: "Group")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_card(block, page: page, placement: :group)

    assert_selector "##{ActionView::RecordIdentifier.dom_id(block)}", text: "Rich text"
    assert_selector "form[data-controller~='admin--saving--autosave']"
    assert_no_selector ".admin-block-card__handle"
    # The handoff's decision 6: the one item a group card's menu has.
    assert_selector "button[aria-label='Block actions']", count: 1
    assert_equal [ "Add note" ], page_menu_items
    assert_no_selector "[data-admin--editor--blocks-target], [data-admin--editor--section-target]"
  end

  test "an unknown placement is refused" do
    page = create_page(title: "Placement")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    assert_raises(ArgumentError) { Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", placement: :tile) }
  end

  test "a card in the list carries a notes marker, for a viewer who can't edit too; an open panel carries none" do
    page = create_page(title: "Noted")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_inline(Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: false))
    assert_selector "#notes-marker-ContentBlock-#{block.id}[data-notes-name='Rich text']"

    render_inline(Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true, placement: :panel))
    assert_no_selector "[data-admin--notes--drawer-target=marker]"

    # A translation tab's group card has no tile to carry it, so it does.
    render_inline(Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "de", editable: true, placement: :group))
    assert_selector "#notes-marker-ContentBlock-#{block.id}"
  end

  test "Add note is the first item of the card's menu, and the delete dialog holds the warning the notes script fills" do
    page = create_page(title: "Noted")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_inline(Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true))

    assert_selector "[role=menu] > :first-child button[data-notes-key='ContentBlock-#{block.id}'][data-notes-compose][data-action='admin--notes--drawer#open']", visible: :all, text: "Add note"
    assert_selector "#delete-block-#{block.id} p[hidden][data-admin--notes--drawer-target=warning][data-notes-within='content_block_#{block.id}']", visible: :all
  end

  # The handoff's decision 6, which replaces the ruling that showed the
  # add-note control at rest where a card had no menu: who can read can write
  # notes (D3), so a card without an editor's menu gets the "⋯" with "Add
  # note" as its only item, and the control is at rest for nobody.
  test "a view-only card and a translation tab's group card have a menu whose only item is Add note; an editor's is unchanged; nothing marks the control as shown at rest" do
    page = create_page(title: "Noted")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    # The card's own menu, in its header: a rich-text field has an Insert menu further down.
    items = -> { self.page.all(".admin-block-card > div:first-child [role=menu] > div", visible: :all).map { |item| item.text(:all).strip } }
    add_note = "[role=menu] button[data-notes-key='ContentBlock-#{block.id}'][data-notes-compose][data-action='admin--notes--drawer#open']"

    render_inline(Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: false))
    assert_selector "button[aria-haspopup=menu][aria-label='Block actions']", count: 1
    assert_equal [ "Add note" ], items.call
    assert_selector add_note, visible: :all
    assert_no_selector ".admin-block-card__handle"
    assert_no_selector "dialog", visible: :all
    assert_no_selector "[data-notes-add]"

    # A translation tab's group card, which had no menu for anyone.
    [ true, false ].each do |editable|
      render_inline(Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "de", editable: editable, placement: :group))
      assert_equal [ "Add note" ], items.call
      assert_selector add_note, visible: :all
      assert_no_selector "[data-notes-add]"
    end

    render_inline(Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true))
    assert_equal [ "Add note", "Move up", "Move down", "Move into section…", "Duplicate", "", "Delete block…" ], items.call
    assert_no_selector "[data-notes-add]"

    # An open form in a section has neither: its tile carries both.
    render_inline(Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: false, placement: :panel))
    assert_no_selector "[role=menu]", visible: :all
  end

  test "a block's delete dialog marks its notes warning as alone in its box, and the shared dialog's box is as it was" do
    page = create_page(title: "Noted")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)

    render_inline(Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true))

    assert_selector "#delete-block-#{block.id} div[class='mt-2 text-ink'] > p[hidden][data-admin--notes--drawer-target=warning][data-notes-alone]", visible: :all
  end

  # ----- Held by someone else (live-editing Task 7; handoff 1 to 7, 18, 26) -----

  A = "tab-aaaaaaaa".freeze
  B = "tab-bbbbbbbb".freeze

  def controls = form_controls

  def held_setup(type: "post_list", **attributes)
    @held_page = create_page(title: "Held")
    @held_block = @held_page.content_blocks.create!(block_type: type, position: 0, settings: { "limit" => 3 }, **attributes)
    @dana = users(:two)
    @dana.update!(name: "Dana Weiss")
  end

  def render_for(viewer, tab, **options)
    as_viewer(viewer, tab: tab) { render_inline Admin::EditorScreen::BlockCardComponent.new(page: @held_page, block: @held_block, locale: "en", **options) }
  end

  test "held by someone else: the strip is in its slot, the unit says held, the form has no autosave controller, every control is readonly or disabled and holds the same name and value as the editable form's" do
    held_setup
    render_for(users(:one), A)
    editable_controls = controls
    assert_selector "form[data-controller~='admin--saving--autosave']"

    reserve(@held_block, @held_page, @dana, B)
    render_for(users(:one), A)

    assert_selector "#content_block_#{@held_block.id}[data-editing-unit][data-editing-held=true]"
    assert_selector "#block-#{@held_block.id}-hold[data-editing-strip-slot] [data-editing-kind=held]", text: "Dana Weiss is editing this block"
    assert_no_selector "[data-controller~='admin--saving--autosave']"
    assert_equal editable_controls, controls
    assert_selector "fieldset.admin-held"
    Capybara.string(rendered_content).all("fieldset.admin-held input, fieldset.admin-held textarea, fieldset.admin-held select, fieldset.admin-held button", visible: :all).each do |node|
      next if node["type"] == "hidden"

      assert node["readonly"] || node["disabled"], "#{node.tag_name} #{node['name']} must be read-only"
    end
  end

  test "held by the viewer in this tab: drawn as ever" do
    held_setup
    reserve(@held_block, @held_page, users(:one), A)

    render_for(users(:one), A)

    assert_selector "form[data-controller~='admin--saving--autosave']"
    assert_no_selector "[data-editing-held]"
    assert_selector "#block-#{@held_block.id}-hold[data-editing-strip-slot]:empty"
    assert_no_selector "fieldset.admin-held"
  end

  test "held by the viewer in another tab: read-only, with the own-tab strip" do
    held_setup
    reserve(@held_block, @held_page, users(:one), B)

    render_for(users(:one), A)

    assert_no_selector "[data-controller~='admin--saving--autosave']"
    assert_selector "#block-#{@held_block.id}-hold", text: "You're editing this in another tab"
  end

  test "held by nobody: the slot is there and empty" do
    held_setup

    render_for(users(:one), A)

    assert_selector "#block-#{@held_block.id}-hold[data-editing-strip-slot]:empty"
  end

  test "the card's border is line-strong and its menu has Take over first (handoff 2, 3)" do
    held_setup
    reserve(@held_block, @held_page, @dana, B)

    render_for(users(:one), A)

    assert_selector "#content_block_#{@held_block.id}.border-line-strong"
    assert_no_selector "#content_block_#{@held_block.id}.border-line"
    items = Capybara.string(rendered_content).all(".admin-block-card > div:first-child [role=menu] [role=none]", visible: :all).map { |item| item.text(:all).strip }
    assert_equal [ "Take over", "Add note", "Move up", "Move down", "Move into section…", "Duplicate", "", "Delete block…" ], items
    assert_selector "[role=menu] button[type=button][data-action='admin--editing--hold#takeOver']", text: "Take over", visible: :all
    assert_selector "[role=menu] button[data-move='up']:not([disabled]), [role=menu] form[action$='/duplicate']", visible: :all
  end

  test "someone who may only read sees the strip without Take over and the ordinary border (handoff 26)" do
    held_setup
    reserve(@held_block, @held_page, @dana, B)

    render_for(users(:reader), A, editable: false)

    assert_selector "#block-#{@held_block.id}-hold", text: "Dana Weiss is editing this block"
    assert_no_selector "#block-#{@held_block.id}-hold button"
    assert_no_selector "button", text: "Take over", visible: :all
    assert_selector "#content_block_#{@held_block.id}.border-line"
    assert_no_selector "#content_block_#{@held_block.id}.border-line-strong"
  end

  test "the rich-text field of a held card has no toolbar and says read-only (handoff 7)" do
    held_setup(type: "rich_text", body: rich_doc("Words"))
    render_for(users(:one), A)
    assert_selector "[role=toolbar]"
    assert_selector "[data-controller~='admin--rich-text--editor'][data-admin--rich-text--editor-read-only-value=false]"

    reserve(@held_block, @held_page, @dana, B)
    render_for(users(:one), A)

    assert_no_selector "[role=toolbar]", visible: :all
    assert_selector "[data-controller~='admin--rich-text--editor'][data-admin--rich-text--editor-read-only-value=true]"
  end

  test "the card's buttons outside its form keep working while it is held: move, duplicate, delete" do
    held_setup
    reserve(@held_block, @held_page, @dana, B)

    render_for(users(:one), A)

    assert_selector "[role=menu] button[data-action='click->admin--editor--blocks#moveDown']:not([disabled])", visible: :all
    assert_selector "[role=menu] form[action$='/duplicate'] button:not([disabled])", visible: :all
    assert_selector "[role=menu] button[data-action*='dialog']:not([disabled]), [role=menu] button.text-danger-ink:not([disabled])", visible: :all
    assert_selector ".admin-block-card__handle:not([disabled])"
  end

  test "the card's version differs between free, held by another and held by the viewer's other tab, and a hold of the viewer in this tab is the free one" do
    held_setup
    version = lambda do |viewer, tab|
      render_for(viewer, tab)
      Capybara.string(rendered_content).find("#content_block_#{@held_block.id}", visible: :all)["data-editing-version"]
    end
    free = version.(users(:one), A)

    reserve(@held_block, @held_page, users(:one), A)
    assert_equal free, version.(users(:one), A), "held by the viewer in this tab renders as the free card does"
    other_tab = version.(users(:one), B)

    Editing::Reservation.where(subject: @held_block).delete_all # version: none (a test clears a reservation)
    reserve(@held_block, @held_page, @dana, B)
    by_other = version.(users(:one), A)

    assert_equal 3, [ free, other_tab, by_other ].uniq.size
  end

  test "a block in a section, held by someone else: its hidden panel is read-only with the strip in its slot (Review Focus 4)" do
    held_setup(type: "rich_text", body: rich_doc("Words"))
    section = @held_page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "two" })
    @held_block.update!(section: section, section_column: 1)
    reserve(@held_block, @held_page, @dana, B)

    render_for(users(:one), A, placement: :panel)

    assert_selector "#block-#{@held_block.id}-panel[hidden][data-editing-held=true]", visible: :all
    assert_selector "#block-#{@held_block.id}-panel #block-#{@held_block.id}-hold [data-editing-kind=held]", visible: :all
    assert_no_selector "[data-controller~='admin--saving--autosave']", visible: :all
    assert_selector "#block-#{@held_block.id}-panel fieldset.admin-held", visible: :all
  end

  test "one read of the holds serves the card: a Holds handed over is the only query for it" do
    held_setup
    holds = as_viewer(users(:one), tab: A) { Editing::Holds.on(@held_page, viewer: Current.user, tab: A) }

    statements = capture_sql { render_for(users(:one), A, holds: holds) }.grep(/edit_reservations/)

    assert_empty statements
  end
end
