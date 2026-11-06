require "application_system_test_case"

class Admin::SectionsPointerSystemTest < Admin::SectionsSystemTestCase
  # ---- The pointer ----

  def slot_in(container) = "!!document.querySelector(#{"#{container} > .admin-drag-ghost".to_json})"

  test "the pointer drags a tile from one lane to the other" do
    open_editor

    mouse = drag_to("#{tile(@left)} .admin-block-tile__grip", lane(2))
    assert_selector "body > .admin-drag-fallback"
    assert_no_selector "body > .admin-drag-fallback[id], body > .admin-drag-fallback [id]", visible: :all
    await_js slot_in(lane(2))
    mouse.up

    assert_eventually { @left.reload.section_column == 2 }
    assert_writes_settled
    assert_no_selector ".admin-drag-fallback"
    assert_equal [ @right.id, @left.id ], tiles_in(2)
    assert_equal [ @right.id, @left.id ], @page.content_blocks.in_column(@section, 2).reorder(:position).ids
    assert_empty tiles_in(1)
  end

  test "the pointer drags a card into an empty lane, where it becomes a tile" do
    @right.destroy!
    card = @page.content_blocks.create!(block_type: "post_list", position: 1)
    open_editor

    mouse = drag_to("#{tile(card)} .admin-block-card__handle", lane(2))
    await_js slot_in(lane(2))
    mouse.up

    assert_selector "#{lane(2)} > .admin-block-tile[data-block-id='#{card.id}']"
    assert_equal [ @section.id, 2 ], card.reload.then { |b| [ b.section_id, b.section_column ] }
    assert_equal [ @section.id ], cards_in_list
  end

  test "the pointer drags a tile out of its section into the page's list, where it becomes a card" do
    below = @page.content_blocks.create!(block_type: "post_list", position: 1)
    open_editor

    mouse = drag_to("#{tile(@left)} .admin-block-tile__grip", "#{tile(below)} .admin-block-card__handle")
    await_js slot_in("#content-blocks-list")
    mouse.up

    assert_selector "#content-blocks-list > .admin-block-card[data-block-id='#{@left.id}']"
    assert_nil @left.reload.section_id
    assert_equal [ @section.id, below.id, @left.id ].sort, @page.content_blocks.top_level.ids.sort
    assert_writes_settled
    assert_equal @page.content_blocks.top_level.reorder(:position).ids, cards_in_list
  end

  # A section's card dragged over another section: its lanes refuse it (a
  # section never holds a section), and the list takes it as it takes any
  # card. And the drag is seen through: every lane of the dragged card is
  # disconnected and connected again each time the card moves in the list, and
  # a Sortable destroyed then would end the drag where it was.
  test "the pointer drags a section's card past another section and a card, to the end of the list" do
    other = @page.content_blocks.create!(block_type: "section", position: 1)
    inside = @page.content_blocks.create!(block_type: "image", section: other, section_column: 1, position: 0)
    last = @page.content_blocks.create!(block_type: "image", position: 2)
    open_editor

    mouse = drag_to("#{tile(@section)} > div:first-child .admin-block-card__handle", tile(last))
    await_drag_slot "#content-blocks-list > .admin-drag-ghost", at: :last
    assert_no_selector "#{lane(1, other)} > .admin-drag-ghost, #{lane(2, other)} > .admin-drag-ghost", visible: :all
    mouse.up

    assert_eventually { @page.content_blocks.top_level.reorder(:position).ids == [ other.id, last.id, @section.id ] }
    assert_writes_settled
    assert_equal [ other.id, last.id, @section.id ], cards_in_list
    assert_equal [ other.id, 1 ], inside.reload.then { |b| [ b.section_id, b.section_column ] }
    assert_equal @section.id, @left.reload.section_id

    # The lanes that travelled with the card still take a drop.
    mouse = drag_to("#{tile(@left)} .admin-block-tile__grip", lane(2))
    await_js slot_in(lane(2))
    mouse.up
    assert_eventually { @left.reload.section_column == 2 }
    assert_writes_settled
  end
end
