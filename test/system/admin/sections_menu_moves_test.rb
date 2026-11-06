require "application_system_test_case"

class Admin::SectionsMenuMovesSystemTest < Admin::SectionsSystemTestCase
  # ---- Every move from the menu, by keyboard (sections spec §1, §4.4) -------
  #
  # A tile's grip is for the pointer, so its "⋯" menu is the only way a
  # keyboard user moves a block that is in a section; a top-level card's menu
  # is how one gets into a section without a drag. These tests work the menus
  # with keys alone -- the button is focused by script, because `send_keys` on
  # an element clicks it first, which would be the pointer opening the menu --
  # and each says where the focus is afterwards: never on <body>.

  def assert_focus_on(selector, what)
    assert_eventually(message: -> { "the focus is not on #{what}, but on #{page.evaluate_script("document.activeElement?.outerHTML.slice(0, 160)")}" }) { focus_is_on(selector) }
  end

  test "Move down and Move up reorder a lane from the keyboard, and the focus stays on the tile's menu" do
    below = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 1)
    open_editor
    assert_selector "#{tile(@left)} button[data-move='up'][disabled]", visible: :all

    pick_by_keyboard(tile(@left), "Move down")

    assert_eventually { @page.content_blocks.in_column(@section, 1).reorder(:position).ids == [ below.id, @left.id ] }
    assert_equal [ below.id, @left.id ], tiles_in(1)
    assert_selector "#{tile(@left)} button[data-move='down'][disabled]", visible: :all
    assert_selector "#{tile(below)} button[data-move='up'][disabled]", visible: :all
    assert_no_selector "#{tile(@left)} [role=menu]"
    assert_focus_on menu_button(tile(@left)), "the moved tile's menu"
    assert_no_selector "#toasts .admin-toast", text: "Undo"

    pick_by_keyboard(tile(@left), "Move up")

    assert_eventually { @page.content_blocks.in_column(@section, 1).reorder(:position).ids == [ @left.id, below.id ] }
    assert_focus_on menu_button(tile(@left)), "the moved tile's menu"
    assert_writes_settled
  end

  # Along one lane nothing is redrawn and nothing held, so the focus is on the
  # tile's menu as soon as the tile has moved, not only once the answer is in.
  test "a tile moved along its lane has the focus at once, while its move is still on the wire" do
    below = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 1)
    open_editor
    script_writes("hold")

    pick_by_keyboard(tile(@left), "Move down")

    await_js "window.__release.length === 1"
    assert_equal [ below.id, @left.id ], tiles_in(1)
    assert focus_is_on(menu_button(tile(@left))), "the focus is not on the moved tile's menu while its move is out"
    assert_no_selector "#{tile(@left)} [role=menu]"

    page.execute_script("window.__release[0]()")
    assert_writes_settled
    assert_equal [ below.id, @left.id ], @page.content_blocks.in_column(@section, 1).reorder(:position).ids
    assert focus_is_on(menu_button(tile(@left)))
  end

  # By keys alone, the dialog included: Enter on the item opens it with the
  # focus on the select, which holds the one other column; Tab, Tab is Move.
  test "Move to column… moves a tile to the end of the chosen lane, and the focus follows it" do
    open_editor

    pick_by_keyboard(tile(@left), "Move to column…")
    assert_selector "#move-block-dialog[open]"
    assert_equal [ "Column 2" ], page.all("#move-block-destination option").map(&:text)
    assert_focus_on "#move-block-destination", "the dialog's select"
    keyboard.type(:tab, :tab)
    assert_equal "Move", focused_text
    keyboard.type(:enter)

    assert_no_selector "#move-block-dialog[open]"
    assert_eventually { @left.reload.section_column == 2 }
    assert_equal [ @right.id, @left.id ], @page.content_blocks.in_column(@section, 2).reorder(:position).ids
    assert_selector "#{lane(2)} > .admin-block-tile", count: 2
    assert_equal [ @right.id, @left.id ], tiles_in(2)
    assert_writes_settled
    assert_focus_on menu_button(tile(@left)), "the moved tile's menu"
    # Its form says the new column, and is still the one form the block has.
    find(face(@left)).click
    assert_selector panel(@left), text: "Image · column 2"
    assert_selector "[id='block-#{@left.id}-panel']", count: 1, visible: :all
  end

  test "Escape in the Move dialog moves nothing and gives the focus back to the tile's menu" do
    open_editor
    count_writes

    pick_by_keyboard(tile(@left), "Move to column…")
    assert_focus_on "#move-block-destination", "the dialog's select"
    keyboard.type(:escape)

    assert_no_selector "#move-block-dialog[open]"
    assert_focus_on menu_button(tile(@left)), "the tile's menu"
    assert_equal [ @left.id ], tiles_in(1)
    await_frames # a move would have been queued and sent by Move's own click
    assert_equal [], page.evaluate_script("window.__writes")
  end

  test "Move to column… is disabled in a section of one column, and enabled again by a second" do
    @section.update!(settings: { "layout" => "one" })
    @right.update_columns(section_column: 1, position: 1)
    open_editor
    assert_selector "#{tile(@left)} button[data-move='column'][disabled]", visible: :all
    assert_selector "#{tile(@right)} button[data-move='column'][disabled]", visible: :all

    find(layout_button).click
    find("#{section_card} [role=menuitem][data-admin--editor--section-layout-param='two']").click

    assert_selector "#section-#{@section.id}-lanes [data-admin--editor--blocks-target='lane']", count: 2
    assert_selector "#{tile(@left)} button[data-move='column']:not([disabled])", visible: :all
    assert_writes_settled
  end

  test "Move out of section puts the block right after the section as a card, with the focus on it" do
    last = @page.content_blocks.create!(block_type: "image", position: 1)
    open_editor

    pick_by_keyboard(tile(@left), "Move out of section")

    assert_selector card(@left)
    assert_writes_settled
    assert_equal [ @section.id, @left.id, last.id ], @page.content_blocks.top_level.reorder(:position).ids
    assert_equal [ @section.id, @left.id, last.id ], cards_in_list
    assert_nil @left.reload.section_id
    assert_no_selector panel(@left), visible: :all
    assert_selector "#section-#{@section.id}-summary", text: "1 block"
    assert_focus_on "#{card(@left)} .admin-block-card__handle", "the handle of the card the block became"
    # One delete dialog for the block: the tile's went with the tile.
    assert_selector "[id='delete-block-#{@left.id}']", count: 1, visible: :all
    assert_no_selector "#toasts .admin-toast", text: "Undo"
  end

  test "Move into section… offers every column of every section, and is disabled without one" do
    block = @page.content_blocks.create!(block_type: "image", position: 1)
    second = @page.content_blocks.create!(block_type: "section", position: 2, settings: { "layout" => "three" })
    open_editor
    scope = "##{ActionView::RecordIdentifier.dom_id(block)}"

    pick_by_keyboard(scope, "Move into section…")
    within("#move-block-dialog") do
      assert_equal [ "Section 1 · column 1", "Section 1 · column 2", "Section 2 · column 1", "Section 2 · column 2", "Section 2 · column 3" ],
        page.all("option").map(&:text)
      select "Section 2 · column 3", from: "move-block-destination"
    end
    page.execute_script("document.querySelector('#move-block-dialog button[data-action=\"admin--editor--blocks#moveTo\"]').focus()")
    keyboard.type(:enter)

    assert_eventually { block.reload.then { |b| [ b.section_id, b.section_column ] } == [ second.id, 3 ] }
    assert_selector "#{lane(3, second)} > .admin-block-tile[data-block-id='#{block.id}']"
    assert_writes_settled
    assert_equal [ @section.id, second.id ], cards_in_list
    assert_selector "#section-#{second.id}-summary", text: "1 block"
    assert_focus_on menu_button("#{lane(3, second)} > .admin-block-tile"), "the menu of the tile the card became"
    # The tile it became opens its form, under the section it went into.
    find("#{lane(3, second)} .admin-block-tile__face").click
    assert_selector "#section-#{second.id}-panels > #block-#{block.id}-panel", text: "Image · column 3"

    plain = create_page(title: "No sections")
    plain.content_blocks.create!(block_type: "image", position: 0)
    visit_editor(plain)
    assert_selector "button[data-move='into'][disabled]", visible: :all
  end

  # A section's card is added and removed without the other cards being drawn
  # again, so it is the screen that says whether there is one to move into.
  test "Move into section… is enabled when the page gains a section and disabled when it loses its last" do
    plain = create_page(title: "Gains a section")
    block = plain.content_blocks.create!(block_type: "image", position: 0)
    visit_editor(plain)
    scope = "##{ActionView::RecordIdentifier.dom_id(block)}"
    assert_selector "#{scope} button[data-move='into'][disabled]", visible: :all

    within("#block-picker-end") { press "Section" }

    assert_selector ".admin-section-card [data-admin--editor--blocks-target='lane']", count: 2
    assert_selector "#{scope} button[data-move='into']:not([disabled])", visible: :all
    assert_writes_settled

    find(".admin-section-card button[aria-label='Section actions']").click
    press "Delete section and its blocks…"
    within("dialog[open]") { press "Delete section" }

    assert_no_selector ".admin-section-card"
    assert_selector "#{scope} button[data-move='into'][disabled]", visible: :all
    assert_writes_settled
  end

  # A collapsed section shows one line: a block moved into it would be gone
  # from the screen, and nothing would be left to take the focus.
  test "a block moved into a collapsed section opens the section" do
    block = @page.content_blocks.create!(block_type: "image", position: 1)
    open_editor
    find("#{section_card} button[aria-expanded]", text: "Section").click
    assert_no_selector lane(1)
    scope = "##{ActionView::RecordIdentifier.dom_id(block)}"

    pick_by_keyboard(scope, "Move into section…")
    within("#move-block-dialog") { select "Section 1 · column 2", from: "move-block-destination" }
    page.execute_script("document.querySelector('#move-block-dialog button[data-action=\"admin--editor--blocks#moveTo\"]').focus()")
    keyboard.type(:enter)

    assert_selector "#{lane(2)} > .admin-block-tile[data-block-id='#{block.id}']"
    assert_selector "#{section_card} button[aria-expanded='true']", text: "Section"
    assert_writes_settled
    assert_equal [ @section.id, 2 ], block.reload.then { |b| [ b.section_id, b.section_column ] }
    assert_focus_on menu_button("#{lane(2)} > .admin-block-tile[data-block-id='#{block.id}']"), "the menu of the tile the card became"
  end

  # Review gap 2: the copy of a block in a column is drawn in that column,
  # after its source. Not opened (see `copy_tile_streams`): the form that was
  # open stays open.
  test "Duplicate from a tile's menu puts the copy's tile after its source, unopened, with the focus on its menu" do
    below = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 1)
    open_editor
    find(face(@right)).click
    assert_selector panel(@right)

    pick_by_keyboard(tile(@left), "Duplicate")

    assert_selector "#{lane(1)} > .admin-block-tile", count: 3
    assert_writes_settled
    copy = (@page.content_blocks.in_column(@section, 1).to_a - [ @left, below ]).sole
    assert_equal [ @left.id, copy.id, below.id ], @page.content_blocks.in_column(@section, 1).reorder(:position).ids
    assert_equal [ @left.id, copy.id, below.id ], tiles_in(1)
    assert_equal [ @section.id ], cards_in_list
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 4 blocks", exact_text: true
    assert_selector "#section-#{@section.id}-panels > #{panel(copy)}", visible: :all
    assert_no_selector panel(copy)
    assert_selector panel(@right)
    assert_focus_on menu_button(tile(copy)), "the copy's menu"
    assert_selector "#{tile(copy)} button[data-move='up']:not([disabled])", visible: :all

    # The copy is a block like any: its form opens and saves on its own base.
    find(face(copy)).click
    fill_in id: caption(copy), with: "The copy's own caption"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{copy.id}-save-status", text: "SAVED"
    assert_writes_settled
    assert_equal [ "The copy's own caption", nil ], [ copy.reload.caption, @left.reload.caption ]
  end

  # Review gap 1: the delete dialog is the tile's, so it opens while the
  # block's form -- the hidden panel it used to be in -- is closed.
  test "Delete block… from a tile's menu asks and deletes with the block's form closed, and leaves no dialog behind" do
    open_editor
    assert_no_selector panel(@left)

    pick_by_keyboard(tile(@left), "Delete block…")
    assert_selector "#delete-block-#{@left.id}[open]", text: "Delete this block?"
    assert_equal "Cancel", focused_text
    keyboard.type(:enter)

    assert_no_selector "dialog[open]"
    assert_selector tile(@left)
    assert_focus_on menu_button(tile(@left)), "the tile's menu, after Cancel"
    assert ContentBlock.exists?(@left.id)

    pick_by_keyboard(tile(@left), "Delete block…")
    keyboard.type(:tab)
    assert_equal "Delete block", focused_text
    keyboard.type(:enter)

    assert_no_selector tile(@left)
    assert_no_selector panel(@left), visible: :all
    assert_no_selector "[id='delete-block-#{@left.id}']", visible: :all
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 1 block", exact_text: true
    assert_writes_settled
    assert_not ContentBlock.exists?(@left.id)
  end

  # The dialog travels with the element that stands for the block: the card a
  # tile becomes has its own, and the tile's is gone with the tile.
  test "a block moved out of its section is deleted from its card's menu, through the card's own dialog" do
    open_editor
    pick_by_keyboard(tile(@left), "Move out of section")
    assert_selector card(@left)
    assert_writes_settled

    pick_by_keyboard(card(@left), "Delete block…")
    assert_selector "#{card(@left)} #delete-block-#{@left.id}[open]"
    within("dialog[open]") { press "Delete block" }

    assert_no_selector "[data-block-id='#{@left.id}']", visible: :all
    assert_no_selector "[id='delete-block-#{@left.id}']", visible: :all
    assert_writes_settled
    assert_not ContentBlock.exists?(@left.id)
  end

  # Review gap 3, the refusals. A menu's move that fails is put back like a
  # drop that fails, and the focus goes back with the block.
  test "a menu move that never reaches the server puts the tile back with the focus on its menu" do
    open_editor
    script_writes("fail")

    pick_by_keyboard(tile(@left), "Move out of section")

    assert_selector "#toasts .admin-toast[role=alert]", text: "Couldn't save the new order. Check your connection and try again."
    assert_order_eventually([ @left.id ]) { tiles_in(1) }
    assert_equal [ @section.id ], cards_in_list
    assert_writes_settled
    assert_equal @section.id, @left.reload.section_id
    assert_focus_on menu_button(tile(@left)), "the menu of the tile that was put back"
    assert_not page.evaluate_script("document.querySelector(#{tile(@left).to_json}).inert"), "the tile was left held"
  end

  # The column was folded away in another tab: the refusal redraws the list,
  # and the tile that had the focus is no longer in the page. The block's new
  # tile takes it.
  test "a menu move into a column that is gone redraws the list and puts the focus on the block's new tile" do
    open_editor
    as_unheard(users(:two)) { assert ContentBlocks::Save.call(ContentBlock.find(@section.id), attributes: { settings: { "layout" => "one" } }).ok? }

    pick_by_keyboard(tile(@left), "Move to column…")
    assert_focus_on "#move-block-destination", "the dialog's select"
    keyboard.type(:tab, :tab, :enter)

    assert_selector "#content-blocks-alert", text: "That section or column no longer exists"
    assert_selector "#section-#{@section.id}-lanes [data-admin--editor--blocks-target='lane']", count: 1
    assert_writes_settled
    assert_equal [ @left.id, @right.id ], tiles_in(1)
    assert_equal [ [ 1, 0 ], [ 1, 1 ] ], [ @left, @right ].map { |block| block.reload.then { |b| [ b.section_column, b.position ] } }
    assert_focus_on menu_button(tile(@left)), "the menu of the block's redrawn tile"
    assert_selector "#{tile(@left)} button[data-move='column'][disabled]", visible: :all
  end

  # A block whose form holds a refused save is not moved by a drop
  # (`admin--editor--blocks#move`), and not by the menu either: the same sender.
  test "a block whose form was refused is not moved from the menu: it stays, with its text, and takes the focus back" do
    open_editor
    find(face(@left)).click
    travel 1.minute do
      as_unheard(users(:two)) { ContentBlocks::Save.call(@left, translations: { "en" => { caption: "The other editor's caption" } }) }
    end
    fill_in id: caption(@left), with: "Mine, refused"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE", wait: 8

    pick_by_keyboard(tile(@left), "Move out of section")

    assert_selector "#toasts .admin-toast[role=alert]", text: "Reload or fix this block before moving it."
    assert_order_eventually([ @left.id ]) { tiles_in(1) }
    assert_equal [ @section.id ], cards_in_list
    assert_field caption(@left), with: "Mine, refused"
    assert_equal @section.id, @left.reload.section_id
    assert_focus_on menu_button(tile(@left)), "the menu of the tile that was not moved"
  end

  # ---- Menu moves: an unavailable tile, what is announced, where the focus stays

  def announced = page.evaluate_script("document.querySelector('[data-admin--editor--blocks-target=\"announcer\"]').textContent")

  # Spec §1: the grip moves an unavailable tile, so the menu does too.
  test "a tile of an unregistered type is moved along its lane and out of its section from the keyboard" do
    gone = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    gone.update_column(:block_type, "gone/thing")
    open_editor

    pick_by_keyboard(tile(gone), "Move up")

    assert_eventually { @page.content_blocks.in_column(@section, 1).reorder(:position).ids == [ gone.id, @left.id ] }
    assert_equal [ gone.id, @left.id ], tiles_in(1)
    assert_focus_on menu_button(tile(gone)), "the unavailable tile's menu"
    assert_writes_settled

    pick_by_keyboard(tile(gone), "Move out of section")

    assert_selector "#{card(gone)}[data-card-edge='unavailable']", text: "Unavailable type — gone/thing"
    assert_writes_settled
    assert_equal [ @section.id, gone.id ], @page.content_blocks.top_level.reorder(:position).ids
    assert_nil gone.reload.section_id
    assert_no_selector panel(gone), visible: :all
    assert_equal [ @left.id ], tiles_in(1)
    assert_selector "#section-#{@section.id}-summary", text: "2 columns · 2 blocks", exact_text: true
  end

  # The focus lands on a button every tile names the same, "Block actions":
  # what moved and where is said in the live region, as the handle's keyboard
  # path says it for a card.
  test "a menu move is announced: which block, and where it went" do
    below = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    open_editor

    pick_by_keyboard(tile(@left), "Move down")
    assert_equal "Image moved down. Position 2 of 2.", announced
    assert_eventually { @page.content_blocks.in_column(@section, 1).reorder(:position).ids == [ below.id, @left.id ] }

    pick_by_keyboard(tile(below), "Move to column…")
    assert_focus_on "#move-block-destination", "the dialog's select"
    keyboard.type(:tab, :tab, :enter)
    assert_equal "Rich text moved to column 2. Position 2 of 2.", announced
    assert_eventually { below.reload.section_column == 2 }
    assert_writes_settled

    pick_by_keyboard(tile(below), "Move out of section")
    assert_equal "Rich text moved out of the section. Position 2 of 2.", announced
    assert_selector card(below)
    assert_writes_settled

    pick_by_keyboard(card(below), "Move into section…")
    assert_focus_on "#move-block-destination", "the dialog's select"
    keyboard.type(:tab, :tab, :enter)
    assert_equal "Rich text moved to column 1 of section 1. Position 2 of 2.", announced
    assert_eventually { below.reload.section_column == 1 }
    assert_writes_settled
  end

  test "a menu move that fails is announced as put back" do
    open_editor
    script_writes("fail")

    pick_by_keyboard(tile(@left), "Move out of section")

    assert_selector "#toasts .admin-toast[role=alert]", text: "Couldn't save the new order."
    assert_order_eventually([ @left.id ]) { tiles_in(1) }
    assert_writes_settled
    assert_eventually { announced == "Image is back where it was." }
  end

  # A move along one container holds nothing and redraws nothing, so the end
  # of its turn has no focus to give back: a person who has gone elsewhere
  # while the request was out -- a click on the blank page -- stays there.
  test "after Move up on a top-level card, a focus put elsewhere before the answer lands stays there" do
    first = @page.content_blocks.create!(block_type: "image", position: 1)
    second = @page.content_blocks.create!(block_type: "image", position: 2)
    open_editor
    script_writes("hold")

    pick_by_keyboard(card(second), "Move up")
    await_js "window.__release.length === 1"
    assert focus_is_on("#{card(second)} .admin-block-card__handle"), "the moved card's handle has the focus at once"
    page.execute_script("document.activeElement.blur()")
    assert page.evaluate_script("document.activeElement === document.body")

    page.execute_script("window.__release[0]()")
    assert_selector "#content-blocks-status", text: "SAVED"
    assert_writes_settled
    await_frames # the move's turn has ended: what it would do to the focus is done
    assert page.evaluate_script("document.activeElement === document.body"), "the focus was pulled back to the card"
    assert_equal [ @section.id, second.id, first.id ], @page.content_blocks.top_level.reorder(:position).ids
  end
end
