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
    Editing::Reservation.of(@block).includes(:user).first
  end

  def draw(data: nil, viewer: @olga, placement: :tile, **context)
    render_inline Admin::EditorScreen::HolderAvatarComponent.new(record: @block, viewer: viewer, data: data, placement: placement, label: "Rich text", **context)
  end

  test "a card draws nothing: the strip says it there" do
    draw(data: hold_of, placement: :card)

    assert_no_selector "[data-holder-avatar]"
  end

  test "a block nobody holds draws nothing" do
    draw(data: nil)

    assert_no_selector "[data-holder-avatar]"
  end

  test "the viewer's own hold in this tab draws nothing, from the loader's row and from the page's holds" do
    row = hold_of(@olga, tab: "tab-aaaaaaaa")
    Current.set(editing_tab: "tab-aaaaaaaa") do
      draw(data: row)
      assert_no_selector "[data-holder-avatar]"

      draw(holds: Editing::Holds.on(@editor_page, viewer: @olga, tab: "tab-aaaaaaaa"))
      assert_no_selector "[data-holder-avatar]"
    end
  end

  test "someone else's hold: a 20px avatar with their initials, the shared tooltip and the words for a screen reader" do
    draw(data: hold_of)

    assert_selector "span[data-holder-avatar][data-controller='admin--ui--tooltip'].relative"
    assert_selector "span.size-5.border-line-strong[aria-hidden=true]", text: "DW"
    assert_selector "span.sr-only", text: "Dana Weiss is editing this block"
    assert_selector "span[data-tooltip][hidden]", text: "Dana Weiss is editing this block", visible: :all
    assert_no_selector "button"
    assert_no_selector "[aria-live], [role=status]"
    assert_no_text "Take over"
  end

  test "a reader's screen gets it too: nothing here asks for a right" do
    draw(data: hold_of, viewer: users(:reader))
    assert_selector "[data-holder-avatar]"
  end

  test "the viewer's other tab: their own avatar, in the own tone, and the other-tab words" do
    draw(data: hold_of(@olga, tab: "tab-bbbbbbbb"))

    assert_selector "span.size-5.bg-ink.text-paper", text: "OB"
    assert_selector "span.sr-only", text: "You're editing this in another tab"
  end

  test "the page's holds are asked instead of the row, and a name is text" do
    @dana.update!(name: "<b>Dana</b> Weiss")
    hold_of
    draw(holds: Editing::Holds.on(@editor_page, viewer: @olga, tab: "tab-aaaaaaaa"))

    assert_selector "span.sr-only", text: "<b>Dana</b> Weiss is editing this block"
    assert_no_selector "b"
  end

  test "the loader is one statement for 3 blocks and for 30, leaves out an expired row and reads nothing when holds are handed through" do
    loader = Admin::EditorScreen::HolderAvatarComponent.loader
    blocks = Array.new(30) { |index| @editor_page.content_blocks.create!(block_type: "rich_text", position: index + 1) }
    blocks.each { |block| reserve(block, @editor_page, @dana, "tab-bbbbbbbb") }
    Editing::Reservation.of(blocks.last).update_all(changed_at: Time.current - Editing::HOLD - 1.second) # version: none (a test moves a reservation's clock)

    few = capture_sql { @answer_few = loader.call(blocks.first(3), viewer: @olga) }
    many = capture_sql { @answer_many = loader.call(blocks, viewer: @olga) }

    # The rows, then their users: two statements, however many blocks.
    assert_equal few.size, many.size
    assert_operator many.size, :<=, 2
    assert_equal blocks.first(3).map(&:id).sort, @answer_few.keys.sort
    assert_equal blocks.first(29).map(&:id).sort, @answer_many.keys.sort, "the expired row is left out"

    assert_empty capture_sql { assert_equal({}, loader.call(blocks, viewer: @olga, holds: Editing::Holds.none)) }
    assert_equal({}, loader.call([], viewer: @olga))
    assert_equal({}, loader.call(blocks, viewer: nil))
  end
end
