require "application_system_test_case"

class Admin::SectionsTranslationAndUnavailableSystemTest < Admin::SectionsSystemTestCase
  # ---- The translation view (sections spec §4.5) ----------------------------

  test "on a translation tab a section is a heading over its blocks in reading order, each with its pair of fields" do
    with_locales(%w[en de], default: "en") do
      @left.update!(caption: "Left original")
      @right.update!(caption: "Right original")
      visit_editor(@page, locale: "de")

      assert_selector ".admin-section-group", count: 1
      assert_selector ".admin-section-group > .admin-section-group__head > h3", text: "Section", exact_text: true
      assert_no_selector ".admin-block-tile"
      cards = page.all(".admin-section-group > .admin-block-card").map { |card| card["data-block-id"].to_i }
      assert_equal [ @left.id, @right.id ], cards
      assert_selector "[data-block-id='#{@left.id}'] .admin-translation-pair", text: "Left original"

      fill_in id: "block-#{@right.id}-caption", with: "Rechts"
      page.execute_script("document.activeElement.blur()")
      assert_selector "#block-#{@right.id}-save-status", text: "SAVED"
      assert_writes_settled
      assert_equal "Rechts", Mobility.with_locale(:de) { @right.reload.caption }
      assert_equal "Right original", Mobility.with_locale(:en) { @right.caption }
    end
  end

  # Why the group stands in the list with the section's `data-block-id`: the
  # cards around it are still moved on a translation tab, and the order a move
  # sends is the list's children -- which must name the section or it is
  # refused. The group itself has nothing to move it by.
  test "on a translation tab a card is moved past a section's group, and the group has no handle and no menu but its cards' Add note" do
    with_locales(%w[en de], default: "en") do
      below = @page.content_blocks.create!(block_type: "image", position: 1)
      visit_editor(@page, locale: "de")
      group = "#content-blocks-list > .admin-section-group[data-block-id='#{@section.id}']"

      assert_selector group
      assert_no_selector "#{group} .admin-block-card__handle", visible: :all
      assert_no_selector "#{group} button[aria-label='Section actions']", visible: :all
      # Each card in the group has the "⋯" with "Add note" as its only item
      # (the notes handoff's decision 6), and nothing that moves or deletes.
      assert_equal [ "Add note" ] * all("#{group} > .admin-block-card").size,
        all("#{group} button[aria-label='Block actions'] + [role=menu] :is(button, a)", visible: :all).map { |item| item.text(:all).strip }
      assert_no_selector "#{group} [data-move], #{group} dialog", visible: :all
      # No lane on this tab, so nowhere to move a card into.
      assert_selector "#{card(below)} button[data-move='into'][disabled]", visible: :all

      pick_by_keyboard(card(below), "Move up")

      assert_selector "#content-blocks-status", text: "SAVED"
      assert_writes_settled
      assert_equal [ below.id, @section.id ], cards_in_list
      assert_equal [ below.id, @section.id ], @page.content_blocks.top_level.reorder(:position).ids
      assert_equal @section.id, @left.reload.section_id
    end
  end

  # ---- Small screens (sections spec §4.6) -----------------------------------

  # The breakpoint is the section card's own width (a container query), so
  # only a browser can show it. Wide first: the test would pass on lanes that
  # always stacked.
  test "below the width where the lanes fit side by side they stack, each under its column's label" do
    open_editor
    boxes = <<~JS
      (() => {
        const [first, second] = ["1", "2"].map((n) => document.getElementById("section-#{@section.id}-lane-" + n).getBoundingClientRect())
        return { beside: second.left >= first.right && Math.abs(second.top - first.top) < 2, stacked: second.top >= first.bottom }
      })()
    JS
    label_shown = "(() => { const r = document.querySelector('#section-#{@section.id}-lanes .admin-section-lane:nth-child(2) .admin-section-lane__label').getBoundingClientRect(); return r.width > 1 && r.height > 1 })()"

    assert_eventually(message: "the lanes are not side by side at the full width") { page.evaluate_script(boxes)["beside"] }
    assert_not page.evaluate_script(label_shown), "a column's label is shown although the lanes are side by side"

    page.driver.resize(520, 900)

    assert_eventually(message: "the lanes did not stack at 520px") { page.evaluate_script(boxes)["stacked"] }
    assert page.evaluate_script(label_shown), "a stacked lane does not show its column's label"
    assert_selector ".admin-section-lane__label", text: "Column 2", visible: :all
  ensure
    page.driver.resize(1400, 1400)
  end

  # ---- Unavailable types (sections spec §6) ---------------------------------

  # Spec §6 says Delete is the tile's only action; the menu moves were kept
  # for it on purpose (the grip moves it, so the keyboard must: see
  # `Admin::EditorScreen::BlockTileComponent`). What it loses is Duplicate.
  test "a block of a type that is gone is an Unavailable tile that can be moved and deleted, and not copied" do
    @left.update_columns(block_type: "gone/thing")
    open_editor

    assert_selector tile(@left), text: "Unavailable type — gone/thing"
    find(menu_button(tile(@left))).click
    assert_equal [ "Add note", "Move up", "Move down", "Move to column…", "Move out of section", "Delete block…" ],
      page.all("#{tile(@left)} [role=menu] button").map(&:text)

    within(tile(@left)) { press "Delete block…" }
    within("dialog[open]") { press "Delete block" }

    assert_no_selector tile(@left)
    assert_not ContentBlock.exists?(@left.id)
    assert_selector "#section-#{@section.id}-summary", text: "1 block", exact_text: true
  end

  def lose_the_sections_type
    @section.update_columns(block_type: "gone/section")
  end

  test "a section whose type is gone shows its blocks under the Unavailable type card, and each opens its form" do
    lose_the_sections_type
    open_editor

    assert_selector "#{section_card}[data-card-edge='unavailable']", text: "Unavailable type — gone/section"
    assert_selector section_card, text: "Its blocks are still here. Remove the section and keep them, move them out one by one, or delete it with them."
    assert_equal [ @left.id ], tiles_in(1)
    assert_equal [ @right.id ], tiles_in(2)
    assert_no_selector "#{section_card} .admin-block-card__handle", visible: :all
    assert_no_selector "#{section_card} button[aria-label='Section actions']", visible: :all
    assert_no_selector "#{section_card} [id^='block-picker-']", visible: :all

    find(face(@left)).click
    assert_selector panel(@left), text: "Image · column 1"
    fill_in id: caption(@left), with: "Still editable"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "SAVED"
    assert_writes_settled
    assert_equal "Still editable", @left.reload.caption
  end

  # Its lanes take nothing (`admin--editor--blocks#closed`): the server has no column
  # of it to put a block in. Asked of the controller as SortableJS asks it.
  test "a lane of a section whose type is gone takes no block, sorts nothing and sends no order" do
    lose_the_sections_type
    outside = @page.content_blocks.create!(block_type: "image", position: 1)
    open_editor
    count_writes

    answers = page.evaluate_script(<<~JS)
      (() => {
        const controller = #{blocks_controller}
        const lane = document.querySelector(#{lane(1).to_json})
        const card = document.querySelector(#{card(outside).to_json})
        const tile = document.querySelector(#{tile(@right).to_json})
        const own = document.querySelector(#{tile(@left).to_json})
        controller.move(own, lane, controller.snapshot())
        return { card: controller.accepts(lane, card), tile: controller.accepts(lane, tile), sorts: controller.laneSortables.get(lane).option("sort") }
      })()
    JS

    assert_equal({ "card" => false, "tile" => false, "sorts" => false }, answers)
    await_frames # a request the move had queued would have been sent by now
    assert_writes_settled
    assert_empty page.evaluate_script("window.__writes")
  end

  test "in a section whose type is gone a tile's only move is out, and no card is offered a way in" do
    below = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 1)
    lose_the_sections_type
    outside = @page.content_blocks.create!(block_type: "image", position: 1)
    open_editor

    %w[up down column].each do |move|
      assert_selector "#{tile(@left)} button[data-move='#{move}'][disabled]", visible: :all
      assert_selector "#{tile(below)} button[data-move='#{move}'][disabled]", visible: :all
    end
    assert_selector "#{tile(@left)} button[data-move='out']:not([disabled])", visible: :all
    assert_selector "#{card(outside)} button[data-move='into'][disabled]", visible: :all

    pick_by_keyboard(tile(@left), "Move out of section")

    assert_selector card(@left)
    assert_writes_settled
    assert_no_selector "#content-blocks-alert p"
    assert_equal [ @section.id, @left.id, outside.id ], @page.content_blocks.top_level.reorder(:position).ids
    assert_nil @left.reload.section_id
    assert_equal [ below.id ], tiles_in(1)
    assert_no_selector panel(@left), visible: :all
  end

  # With a real section beside it: the Move dialog offers that one's columns
  # only, and numbers it as the first section -- the unavailable card does
  # not read "Section" and is not counted.
  test "the Move dialog offers no column of a section whose type is gone and does not count it" do
    lose_the_sections_type
    real = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "two" })
    outside = @page.content_blocks.create!(block_type: "image", position: 2)
    open_editor

    pick_by_keyboard(card(outside), "Move into section…")

    assert_selector "dialog[open] #move-block-destination"
    assert_equal [ "Section 1 · column 1", "Section 1 · column 2" ], page.all("#move-block-destination option").map(&:text)
    assert_equal [ "section-#{real.id}-lane-1", "section-#{real.id}-lane-2" ], page.all("#move-block-destination option").map(&:value)
    within("dialog[open]") { press "Cancel" }
    assert_no_selector "dialog[open]"
  end

  test "Delete section and its blocks… on a section whose type is gone says how many blocks go with it, and deletes them" do
    lose_the_sections_type
    open_editor

    within("#{section_card} > div:first-child") { press "Delete section and its blocks…" }

    assert_selector "dialog[open]", text: "This also deletes the 2 blocks in it."
    within("dialog[open]") { press "Delete section" }

    assert_no_selector section_card
    assert_no_selector ".admin-block-tile"
    assert_empty @page.content_blocks.reload
  end

  # The safe way out of a section nobody can read: the wrapper goes, what was
  # in it stays, as cards where it stood and in the order it was read in.
  test "Remove section, keep blocks on a section whose type is gone puts its blocks in its place as cards in reading order" do
    above = @page.content_blocks.create!(block_type: "image", position: 0)
    @section.update_columns(position: 1)
    below_left = @page.content_blocks.create!(block_type: "rich_text", section: @section, section_column: 1, position: 1)
    after = @page.content_blocks.create!(block_type: "image", position: 2)
    lose_the_sections_type
    open_editor

    within("#{section_card} > div:first-child") { press "Remove section, keep blocks" }

    assert_no_selector ".admin-section-card"
    assert_no_text "Unavailable type"
    assert_order_eventually([ above.id, @left.id, below_left.id, @right.id, after.id ]) { cards_in_list }
    assert_selector "#content-blocks-list > .admin-block-card", count: 5
    assert_no_selector ".admin-block-tile"
    assert_writes_settled
    assert_not ContentBlock.exists?(@section.id)
    assert_equal [ above.id, @left.id, below_left.id, @right.id, after.id ], @page.content_blocks.top_level.reorder(:position, :id).ids
    assert_equal [ nil ], @page.content_blocks.reload.map(&:section_id).uniq

    # A lifted block is a card like any other: it saves on its own base.
    fill_in id: caption(@left), with: "Kept, and edited as a card"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "SAVED"
    assert_writes_settled
    assert_equal "Kept, and edited as a card", @left.reload.caption
    assert_no_text "CHANGED ELSEWHERE"
  end

  # The same rule as in a section's menu: the removal's answer replaces the
  # blocks' forms, so it does not run over text that was refused.
  test "Remove section, keep blocks on a section whose type is gone does not run while a form holds text that was refused" do
    lose_the_sections_type
    open_editor
    find(face(@left)).click
    travel 1.minute do
      as_unheard(users(:two)) { ContentBlocks::Save.call(@left, translations: { "en" => { caption: "Theirs" } }) }
    end
    fill_in id: caption(@left), with: "Mine, refused"
    page.execute_script("document.activeElement.blur()")
    assert_selector "#block-#{@left.id}-save-status", text: "CHANGED ELSEWHERE", wait: 8

    within("#{section_card} > div:first-child") { press "Remove section, keep blocks" }

    assert_selector "#toasts #toast-queue-hold[role=alert]", text: "Your last change wasn't saved, so this didn't run."
    assert_selector "#{section_card}[data-card-edge='unavailable']"
    assert_field caption(@left), with: "Mine, refused"
    assert_equal @section.id, @left.reload.section_id
    assert_selector "#{section_card} > div:first-child button:not([disabled])", text: "Remove section, keep blocks"
  end
end
