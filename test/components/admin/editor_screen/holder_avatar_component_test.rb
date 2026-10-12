require "test_helper"

# The tile's avatar of whoever is changing a block (live-editing handoff 4, 18,
# 26): in the slot `editor.block.markers`, on a tile only.
class Admin::EditorScreen::HolderAvatarComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @editor_page = create_page(title: "Avatar")
    @block = @editor_page.content_blocks.create!(block_type: "rich_text", position: 0)
    @dana = users(:two)
    @dana.update!(name: "Dana Weiss")
    @olga = users(:one)
    @olga.update!(name: "Olga Braun")
  end

  def hold_of(user = @dana, tab: "tab-bbbbbbbb")
    reserve(@block, @editor_page, user, tab)
  end

  # The page's holds as the editor reads them once for its screen, for the
  # viewer in `tab`: what both hosts hand the slot as `holds:`.
  def holds(viewer: @olga, tab: "tab-aaaaaaaa") = Editing::Holds.on(@editor_page, viewer: viewer, tab: tab)

  def draw(viewer: @olga, placement: :tile, **context)
    render_inline Admin::EditorScreen::HolderAvatarComponent.new(record: @block, viewer: viewer, data: nil, placement: placement, label: "Rich text", **context)
  end

  test "a card draws nothing: the strip says it there" do
    hold_of
    draw(holds: holds, placement: :card)

    assert_no_selector "[data-holder-avatar]"
  end

  test "a block nobody holds draws nothing" do
    draw(holds: holds)

    assert_no_selector "[data-holder-avatar]"
  end

  # Final review M2/M3: the component had a loader for a host that hands no
  # holds, and read `Current.editing_tab` to tell the viewer's own tab. No
  # host needed either: the holds are the slot's context.
  test "a host that hands no holds draws no avatar, reads nothing and asks no Current" do
    hold_of
    Current.set(editing_tab: "tab-aaaaaaaa") do
      assert_empty capture_sql { draw }
    end

    assert_no_selector "[data-holder-avatar]"
    assert_not_respond_to Admin::EditorScreen::HolderAvatarComponent, :loader
    assert_no_match(/Current\b/, Rails.root.join("app/components/admin/editor_screen/holder_avatar_component.rb").read.lines.reject { |line| line.strip.start_with?("#") }.join)
  end

  test "the viewer's own hold in this tab draws nothing" do
    hold_of(@olga, tab: "tab-aaaaaaaa")
    draw(holds: holds)

    assert_no_selector "[data-holder-avatar]"
  end

  test "someone else's hold: a 20px avatar with their initials, the shared tooltip and the words for a screen reader" do
    hold_of
    draw(holds: holds)

    assert_selector "span[data-holder-avatar][data-controller='admin--ui--tooltip'].relative"
    assert_selector "span.size-5.border-line-strong[aria-hidden=true]", text: "DW"
    assert_selector "span.sr-only", text: "Dana Weiss is editing this block"
    assert_selector "span[data-tooltip][hidden]", text: "Dana Weiss is editing this block", visible: :all
    assert_no_selector "button"
    assert_no_selector "[aria-live], [role=status]"
    assert_no_text "Take over"
  end

  test "a reader's screen gets it too: nothing here asks for a right" do
    hold_of
    draw(holds: holds(viewer: users(:reader)), viewer: users(:reader))
    assert_selector "[data-holder-avatar]"
  end

  test "the viewer's other tab: their own avatar, in the own tone, and the other-tab words" do
    hold_of(@olga, tab: "tab-bbbbbbbb")
    draw(holds: holds)

    assert_selector "span.size-5.bg-ink.text-paper", text: "OB"
    assert_selector "span.sr-only", text: "You're editing this in another tab"
  end

  test "a name is text" do
    @dana.update!(name: "<b>Dana</b> Weiss")
    hold_of
    draw(holds: holds)

    assert_selector "span.sr-only", text: "<b>Dana</b> Weiss is editing this block"
    assert_no_selector "b"
  end

  test "drawing from the page's holds costs no statement, for one block as for thirty" do
    blocks = Array.new(30) { |index| @editor_page.content_blocks.create!(block_type: "rich_text", position: index + 1) }
    blocks.each { |block| reserve(block, @editor_page, @dana, "tab-bbbbbbbb") }
    read = holds
    read.other(blocks.first) # the screen's one read, made before any card is drawn

    statements = capture_sql do
      blocks.each do |block|
        render_inline Admin::EditorScreen::HolderAvatarComponent.new(record: block, viewer: @olga, data: nil, placement: :tile, label: "Rich text", holds: read)
        assert_selector "[data-holder-avatar]"
      end
    end
    assert_empty statements
  end
end
