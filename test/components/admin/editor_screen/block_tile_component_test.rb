require "test_helper"

# A block's tile in a section's lane (sections spec §4.2, §4.4): its face, and
# -- for a viewer who may edit -- the grip the pointer drags it by, the "⋯"
# menu that is every move's keyboard path, and the block's delete dialog.
class Admin::EditorScreen::BlockTileComponentTest < ViewComponent::TestCase
  include ContentHelper
  include GalleryAlbum

  setup do
    @editor_page = create_page(title: "Tile")
    @section = @editor_page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    @block = @editor_page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 0)
  end

  def render_tile(block = @block, editable: true)
    render_inline Admin::EditorScreen::BlockTileComponent.new(page: @editor_page, block: block, locale: "en", editable: editable)
  end

  def menu_items = Capybara.string(rendered_content).all("[role=menu] [role=none]", visible: :all).map { |item| item.text(:all).strip }

  test "the tile shows the type's icon in place of its name, and the face is still named by the type" do
    render_tile

    assert_selector ".admin-block-tile__face [data-block-icon=image][class~='text-meta'] svg[class~='size-3']"
    assert_selector ".admin-block-tile__face .sr-only", text: "Image"
    assert_selector ".admin-block-tile__face > span:first-child.sr-only", text: "Image"
    assert_no_selector ".admin-block-tile__face span.font-semibold", text: "Image"
  end

  # Plan ruling 12: a note's tile shows its kind's icon, under the id a
  # save's answer replaces, one icon only, and the face still says "Note".
  test "a note's tile shows its kind's icon in place of the type's name, once, and the face is still named Note" do
    block = @editor_page.content_blocks.create!(block_type: "note", section: @section, section_column: 2, position: 0, settings: { "kind" => "warning" })
    render_tile(block)

    assert_selector ".admin-block-tile__face span#block-#{block.id}-icon-tile[data-block-icon=triangle_alert][class~='text-meta'] svg[class~='size-3']"
    assert_selector ".admin-block-tile__face [data-block-icon]", count: 1
    assert_selector ".admin-block-tile__face .sr-only", text: "Note"
    assert_selector ".admin-block-tile__face", text: /Warning · Empty/
  end

  # Review focus 3.
  test "a type that names no icon keeps its name on the tile and draws no icon anywhere" do
    with_gallery_album do
      block = @editor_page.content_blocks.create!(block_type: "gallery/album", section: @section, section_column: 2, position: 0)
      render_tile(block)

      assert_selector ".admin-block-tile__face span.font-semibold", text: "Album"
      assert_no_selector "[data-block-icon]"
      render_inline Admin::EditorScreen::BlockPickerComponent.new(page: @editor_page, locale: "en")
      assert_selector "#block-picker-end button", text: "Album"
    end
  end

  test "an editable tile's menu lists every move, Duplicate, a divider, then Delete block…, in that order" do
    render_tile

    assert_selector "button[aria-haspopup='menu'][aria-label='Block actions']", text: "⋯"
    assert_equal [ "Add note", "Move up", "Move down", "Move to column…", "Move out of section", "Duplicate", "", "Delete block…" ], menu_items
    assert_selector "[role=menu][data-action~='click->admin--ui--menu#select']", visible: :all
    assert_selector "[role=menu] button[data-move='up'][data-action='click->admin--editor--blocks#moveUp']", visible: :all
    assert_selector "[role=menu] button[data-move='down'][data-action='click->admin--editor--blocks#moveDown']", visible: :all
    assert_selector "[role=menu] button[data-move='out'][data-action='click->admin--editor--blocks#moveOut']", visible: :all
    assert_selector "[role=menu] form[action$='/content_blocks/#{@block.id}/duplicate'][method='post']", visible: :all
    assert_selector "[role=menu] button.text-danger-ink", text: "Delete block…", visible: :all
  end

  # One click, two actions, in this order: `admin--editor--blocks` fills the dialog's
  # choices from the screen, then `admin--ui--dialog` shows it -- so opening,
  # where the focus goes and where it returns are the dialog controller's own.
  test "Move to column… fills the Move dialog and then opens it" do
    render_tile

    assert_selector "[role=menu] button[data-move='column'][data-action='click->admin--editor--blocks#askWhere admin--ui--dialog#open'][data-admin--ui--dialog-id-param='move-block-dialog']",
      text: "Move to column…", visible: :all
  end

  # The dialog is the tile's, not the panel's: a panel is hidden while its
  # form is closed, and a dialog in a hidden element can't be shown.
  test "the block's delete dialog is in the tile, with the delete form" do
    render_tile

    assert_selector "[role=menu] button[data-admin--ui--dialog-id-param='delete-block-#{@block.id}']", text: "Delete block…", visible: :all
    assert_selector ".admin-block-tile > dialog#delete-block-#{@block.id}[data-destructive]", visible: :all
    assert_selector "dialog#delete-block-#{@block.id}", text: "Blocks don’t go to the trash.", visible: :all
    assert_selector "dialog form[action$='/content_blocks/#{@block.id}'] input[name='_method'][value='delete']", visible: :all
    assert_selector "dialog form[action$='/content_blocks/#{@block.id}'] button[type=submit]", text: "Delete block", visible: :all
  end

  # Beside the face a view-only tile has what notes need and nothing of an
  # editor's (notes spec §4.3, D3: a viewer who can only read the page writes
  # notes; the handoff's decision 6: through a menu whose only item is "Add
  # note"), which is why the count here is three.
  test "a view-only tile has its face, its notes marker and a menu with Add note alone: no grip, no move, no dialog" do
    render_tile(editable: false)

    assert_selector ".admin-block-tile > .admin-block-tile__face"
    assert_selector ".admin-block-tile > *", count: 3, visible: :all
    assert_selector ".admin-block-tile > div > [data-admin--notes--drawer-target=marker]", visible: :all
    assert_no_selector ".admin-block-tile__grip", visible: :all
    assert_equal [ "Add note" ], menu_items
    assert_selector "[role=menu] button[data-notes-key='ContentBlock-#{@block.id}'][data-notes-compose][data-action='admin--notes--drawer#open']", visible: :all
    assert_no_selector "[data-move]", visible: :all
    assert_no_selector "dialog", visible: :all
  end

  # Sections spec §1 over §6: the tile keeps its grip, so the pointer can
  # move it along its lane, to another column and out of the section -- and
  # so can the keyboard. Nothing of it can be read, so it is not copied.
  test "a tile of an unregistered type keeps every move and Delete block…, and has no Duplicate" do
    @block.update_column(:block_type, "gone/thing")

    render_tile(@block.reload)

    assert_equal [ "Add note", "Move up", "Move down", "Move to column…", "Move out of section", "", "Delete block…" ], menu_items
    assert_no_selector "form[action$='/duplicate']", visible: :all
    assert_selector "dialog#delete-block-#{@block.id}", visible: :all
  end

  # Sections spec §6. A copy goes into its source's column, and a section
  # whose type is gone has no column left to take one: the save would be
  # refused, so the item that could only fail is not offered.
  test "a tile in a section whose type is gone has no Duplicate" do
    @section.update_column(:block_type, "gone/section")

    render_tile(@block.reload)

    assert_equal [ "Add note", "Move up", "Move down", "Move to column…", "Move out of section", "", "Delete block…" ], menu_items
    assert_no_selector "form[action$='/duplicate']", visible: :all
  end

  # Notes (notes spec §4.3): the marker is for everyone who can read the page;
  # "Add note" in the menu is the path that needs no hover.
  test "a tile carries a notes marker, for a viewer who can't edit too, and Add note first in its menu" do
    render_tile(editable: false)
    assert_selector "#content_block_#{@block.id} > div > #notes-marker-ContentBlock-#{@block.id}[data-notes-name='Image']"

    render_tile
    assert_selector "#notes-marker-ContentBlock-#{@block.id}"
    assert_selector "[role=menu] > :first-child button[data-notes-key='ContentBlock-#{@block.id}'][data-notes-compose][data-action='admin--notes--drawer#open']", visible: :all, text: "Add note"
    assert_selector "#delete-block-#{@block.id} p[hidden][data-admin--notes--drawer-target=warning][data-notes-within='content_block_#{@block.id}']", visible: :all
  end

  # The handoff's decision 6: at rest for nobody.
  test "no tile marks its add-note control as shown at rest" do
    render_tile(editable: false)
    assert_no_selector "[data-notes-add]"

    render_tile
    assert_no_selector "[data-notes-add]"
  end

  test "a tile's version and mark say that its block is held, and differ from the free tile's, for the viewer who is not the holder" do
    render_tile
    free_version = Capybara.string(rendered_content).find("#content_block_#{@block.id}")["data-editing-version"]
    assert_no_selector "[data-editing-held]"

    reserve(@block, @editor_page, users(:two), "tab-bbbbbbbb")
    as_viewer(users(:one), tab: "tab-aaaaaaaa") { render_tile }

    assert_selector "#content_block_#{@block.id}[data-editing-held=true]"
    assert_match(/data-editing-version="[^"]*"\s+data-editing-held="true"/, rendered_content, "the two attributes are separated by whitespace")
    assert_not_equal free_version, Capybara.string(rendered_content).find("#content_block_#{@block.id}")["data-editing-version"]
    assert_selector "[role=menu] button", text: "Move up", visible: :all
    assert_no_selector "button", text: "Take over", visible: :all
  end

  # Review Focus 4 (the plan): the avatar of whoever holds the block stands in
  # the slot before the notes marker, on the tile, with the shared tooltip.
  test "a held block's tile carries the avatar before the notes marker, and no Take over" do
    users(:two).update!(name: "Dana Weiss")
    reserve(@block, @editor_page, users(:two), "tab-bbbbbbbb")
    as_viewer(users(:one), tab: "tab-aaaaaaaa") { render_tile }

    html = rendered_content
    assert_selector "#content_block_#{@block.id} [data-holder-avatar] span.size-5", text: "DW"
    assert_selector "[data-holder-avatar] span.sr-only", text: "Dana Weiss is editing this block"
    assert_selector "[data-holder-avatar] [data-tooltip]", text: "Dana Weiss is editing this block", visible: :all
    assert_operator html.index("data-holder-avatar"), :<, html.index("notes-marker-ContentBlock-#{@block.id}"), "the avatar comes before the notes marker"
    assert_selector "#notes-marker-ContentBlock-#{@block.id}.admin-notes-marker"
    assert_no_text "Take over"
    assert_no_selector "button", text: "Take over", visible: :all
  end

  test "a reader's tile shows the avatar too, and a free tile or one held in this tab shows none" do
    reserve(@block, @editor_page, users(:two), "tab-bbbbbbbb")
    as_viewer(users(:reader), tab: "tab-aaaaaaaa") { render_tile(editable: false) }
    assert_selector "[data-holder-avatar]"

    Editing::Reservation.of(@block).delete_all # version: none (a test clears a reservation)
    as_viewer(users(:one), tab: "tab-aaaaaaaa") { render_tile }
    assert_no_selector "[data-holder-avatar]"

    reserve(@block, @editor_page, users(:one), "tab-aaaaaaaa")
    as_viewer(users(:one), tab: "tab-aaaaaaaa") { render_tile }
    assert_no_selector "[data-holder-avatar]"
  end

  test "the tile's version changes when the avatar would: free, held by another, held by the viewer's other tab" do
    version = lambda do |tab|
      as_viewer(users(:one), tab: tab) { render_tile }
      Capybara.string(rendered_content).find("#content_block_#{@block.id}")["data-editing-version"]
    end
    free = version.call("tab-aaaaaaaa")

    reserve(@block, @editor_page, users(:two), "tab-bbbbbbbb")
    by_another = version.call("tab-aaaaaaaa")

    Editing::Reservation.of(@block).delete_all # version: none (a test clears a reservation)
    reserve(@block, @editor_page, users(:one), "tab-cccccccc")
    by_other_tab = version.call("tab-aaaaaaaa")

    assert_equal 3, [ free, by_another, by_other_tab ].uniq.size
  end

  test "the notes marker is still the one control it was, drawn through the slot" do
    render_tile

    assert_selector "button#notes-marker-ContentBlock-#{@block.id}.admin-notes-marker[aria-label='Add a note on Image'][data-notes-key='ContentBlock-#{@block.id}'][data-notes-name='Image']"
  end
end
