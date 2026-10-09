require "test_helper"

# A block's tile in a section's lane (sections spec §4.2, §4.4): its face, and
# -- for a viewer who may edit -- the grip the pointer drags it by, the "⋯"
# menu that is every move's keyboard path, and the block's delete dialog.
class Admin::EditorScreen::BlockTileComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @page = create_page(title: "Tile")
    @section = @page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    @block = @page.content_blocks.create!(block_type: "image", section: @section, section_column: 1, position: 0)
  end

  def render_tile(block = @block, editable: true)
    render_inline Admin::EditorScreen::BlockTileComponent.new(page: @page, block: block, locale: "en", editable: editable)
  end

  def menu_items = Capybara.string(rendered_content).all("[role=menu] [role=none]", visible: :all).map { |item| item.text(:all).strip }

  test "an editable tile's menu lists every move, Duplicate, a divider, then Delete block…, in that order" do
    render_tile

    assert_selector "button[aria-haspopup='menu'][aria-label='Block actions']", text: "⋯"
    assert_equal [ "Move up", "Move down", "Move to column…", "Move out of section", "Duplicate", "", "Delete block…" ], menu_items
    assert_selector "[role=menu][data-action~='click->admin--menu#select']", visible: :all
    assert_selector "[role=menu] button[data-move='up'][data-action='click->admin--blocks#moveUp']", visible: :all
    assert_selector "[role=menu] button[data-move='down'][data-action='click->admin--blocks#moveDown']", visible: :all
    assert_selector "[role=menu] button[data-move='out'][data-action='click->admin--blocks#moveOut']", visible: :all
    assert_selector "[role=menu] form[action$='/content_blocks/#{@block.id}/duplicate'][method='post']", visible: :all
    assert_selector "[role=menu] button.text-danger-ink", text: "Delete block…", visible: :all
  end

  # One click, two actions, in this order: `admin--blocks` fills the dialog's
  # choices from the screen, then `admin--dialog` shows it -- so opening,
  # where the focus goes and where it returns are the dialog controller's own.
  test "Move to column… fills the Move dialog and then opens it" do
    render_tile

    assert_selector "[role=menu] button[data-move='column'][data-action='click->admin--blocks#askWhere admin--dialog#open'][data-admin--dialog-id-param='move-block-dialog']",
      text: "Move to column…", visible: :all
  end

  # The dialog is the tile's, not the panel's: a panel is hidden while its
  # form is closed, and a dialog in a hidden element can't be shown.
  test "the block's delete dialog is in the tile, with the delete form" do
    render_tile

    assert_selector "[role=menu] button[data-admin--dialog-id-param='delete-block-#{@block.id}']", text: "Delete block…", visible: :all
    assert_selector ".admin-block-tile > dialog#delete-block-#{@block.id}[data-destructive]", visible: :all
    assert_selector "dialog#delete-block-#{@block.id}", text: "Blocks don’t go to the trash. This can’t be undone.", visible: :all
    assert_selector "dialog form[action$='/content_blocks/#{@block.id}'] input[name='_method'][value='delete']", visible: :all
    assert_selector "dialog form[action$='/content_blocks/#{@block.id}'] button[type=submit]", text: "Delete block", visible: :all
  end

  test "a view-only tile has its face and nothing else: no grip, no menu, no dialog" do
    render_tile(editable: false)

    assert_selector ".admin-block-tile > .admin-block-tile__face"
    assert_selector ".admin-block-tile > *", count: 1, visible: :all
    assert_no_selector ".admin-block-tile__grip", visible: :all
    assert_no_selector "[role=menu]", visible: :all
    assert_no_selector "dialog", visible: :all
  end

  # Sections spec §1 over §6: the tile keeps its grip, so the pointer can
  # move it along its lane, to another column and out of the section -- and
  # so can the keyboard. Nothing of it can be read, so it is not copied.
  test "a tile of an unregistered type keeps every move and Delete block…, and has no Duplicate" do
    @block.update_column(:block_type, "gone/thing")

    render_tile(@block.reload)

    assert_equal [ "Move up", "Move down", "Move to column…", "Move out of section", "", "Delete block…" ], menu_items
    assert_no_selector "form[action$='/duplicate']", visible: :all
    assert_selector "dialog#delete-block-#{@block.id}", visible: :all
  end
end
