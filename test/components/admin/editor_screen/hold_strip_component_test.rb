require "test_helper"

# The strip a held card carries, and the two notices that take its place
# (live-editing handoff 1, 2, 13 to 20, 23, 24, 26).
class Admin::EditorScreen::HoldStripComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @page = create_page(title: "Strip")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @post = create_post(title: "Strip post")
    @dana = users(:two)
    @dana.update!(name: "Dana Weiss")
    @olga = users(:one)
    @olga.update!(name: "Olga Braun")
  end

  def hold_by(user, age: 30.seconds) = Editing::Reservation.new(user: user, tab: "tab-aaaaaaaa", changed_at: Time.current - age)

  def strip(subject: @block, hold: hold_by(@dana), viewer: @olga, **options)
    render_inline Admin::EditorScreen::HoldStripComponent.new(subject: subject, hold: hold, viewer: viewer, **options)
  end

  test "a block someone else holds: their avatar, the sentence in 13px ink, Take over, on the sunken strip (handoff 1, 2)" do
    strip

    assert_selector "div.bg-sunken.border-b.border-line.flex.items-center.gap-2[data-admin--editing--hold-target=strip][data-editing-subject='block-#{@block.id}'][data-editing-kind=held]"
    assert_selector "span.size-6[aria-hidden=true]", text: "DW"
    assert_selector "p.text-ink.text-\\[13px\\]", text: "Dana Weiss is editing this block"
    assert_selector "button[data-action='admin--editing--hold#takeOver']", text: "Take over"
    assert_no_selector "[role=alert]"
  end

  test "Take over and Copy my text are the outlined secondary small button, Discard and Remove the small ghost one (handoff 2, 14; the design system's default button)" do
    strip
    assert_selector "button.border.border-line-strong.bg-surface.text-ink.px-2.py-0\\.5", text: "Take over"
    assert_no_selector "button.bg-accent"

    strip(kind: :lost)
    assert_selector "button.border-line-strong.bg-surface", text: "Copy my text"
    assert_selector "button.text-dim", text: "Discard"
    assert_no_selector "button.bg-accent"

    strip(kind: :deleted, hold: nil)
    assert_selector "button.text-dim", text: "Remove"
  end

  test "viewer says whose hold it is: the viewer's own is the own-tab strip without being told" do
    strip(hold: hold_by(@olga), viewer: @olga)

    assert_selector "p", text: "You're editing this in another tab"
  end

  test "Take over is a button of the page, not a link, and never submits" do
    strip

    assert_selector "button[type=button]", text: "Take over"
    assert_no_selector "a", text: "Take over"
  end

  test "a post: 'is editing this post'" do
    strip(subject: @post)

    assert_selector "p", text: "Dana Weiss is editing this post"
    assert_selector "[data-editing-subject=record]"
  end

  test "the page settings: 'is editing the page settings' (handoff 23)" do
    strip(subject: @page)

    assert_selector "p", text: "Dana Weiss is editing the page settings"
  end

  test "one's own other tab: the own avatar and 'You're editing this in another tab' (handoff 18)" do
    strip(hold: hold_by(@olga), own: true)

    assert_selector "span.bg-ink.text-paper", text: "OB"
    assert_selector "p", text: "You're editing this in another tab"
    assert_selector "button", text: "Take over"
  end

  test "someone who may only read sees the strip without Take over (handoff 26)" do
    strip(take_over: false)

    assert_selector "p", text: "Dana Weiss is editing this block"
    assert_no_selector "button"
  end

  test "the strip says in how many milliseconds the hold lapses, never less than 0" do
    strip

    expires = Capybara.string(rendered_content).find("[data-editing-expires-in]")["data-editing-expires-in"].to_i
    assert_in_delta Editing::HOLD.in_milliseconds - 30_000, expires, 1000

    strip(hold: hold_by(@dana, age: 10.minutes))
    assert_selector "[data-editing-expires-in='0']"
  end

  test "it carries the sentences the script shows later: 'Taken over by Dana Weiss' and 'Dana Weiss took over this block' (handoff 13, 19)" do
    strip

    assert_selector "[data-editing-taken-text='Taken over by Dana Weiss · just now']"
    assert_selector "[data-editing-announce='Dana Weiss took over this block']"
    assert_selector "[data-editing-holder='#{@dana.id}']"
  end

  test "lost: the warn alert, role alert, the sentence, Copy my text and Discard (handoff 14, 20, 24)" do
    strip(kind: :lost)

    assert_selector "div.bg-warn-tint.text-warn-ink.border.border-warn[data-editing-kind=lost] > p[role=alert]"
    assert_selector "p", text: "Dana Weiss is editing this block. Your changes weren't saved."
    assert_selector "button[data-action='admin--editing--hold#copy']", text: "Copy my text"
    assert_selector "button[data-action='admin--editing--hold#discard']", text: "Discard"
    assert_selector "span[role=status][aria-live=polite].text-xs.text-ok-ink[data-copied=Copied]", visible: :all
  end

  test "lost, when the hold has lapsed meanwhile: 'Someone else changed this block. Your changes weren't saved.'" do
    strip(kind: :lost, hold: nil)

    assert_selector "p", text: "Someone else changed this block. Your changes weren't saved."
  end

  test "deleted: 'Dana Weiss deleted this block. Your changes weren't saved.', Copy my text and Remove (handoff 15)" do
    strip(kind: :deleted, hold: nil, actor: @dana)

    assert_selector "[role=alert]", text: "Dana Weiss deleted this block. Your changes weren't saved."
    assert_selector "button[data-action='admin--editing--hold#copy']", text: "Copy my text"
    assert_selector "button[data-action='admin--editing--hold#remove']", text: "Remove"
  end

  test "deleted by nobody we can name: 'This block was deleted. …'" do
    strip(kind: :deleted, hold: nil)

    assert_selector "[role=alert]", text: "This block was deleted. Your changes weren't saved."
  end

  test "deleted by the viewer's own other tab: 'You deleted this block in another tab. …'" do
    strip(kind: :deleted, hold: nil, actor: users(:one))

    assert_selector "[role=alert]", text: "You deleted this block in another tab. Your changes weren't saved."
  end

  test "the alert is the sentence alone: the polite 'Copied' status is not inside it (handoff 24)" do
    strip(kind: :lost)

    assert_selector "[data-editing-kind=lost] > p[role=alert]"
    assert_no_selector "[role=alert] [role=status]", visible: :all
    assert_selector "[data-editing-kind=lost] > span[role=status]", visible: :all
    assert_selector "span[data-discard-failed='Couldn\\'t load the block. Try again.']", visible: :all
  end

  test "a name is text, whatever was typed as one" do
    @dana.update!(name: "<b>x</b> y")
    strip

    assert_no_selector "p b"
    assert_selector "p", text: "<b>x</b> y is editing this block"
  end

  test "the name is real text; the avatar's letters are decoration" do
    strip

    assert_selector "span[aria-hidden=true]", text: "DW"
    assert_selector "p:not([aria-hidden])", text: "Dana Weiss"
  end

  test "no colour literal and no lock icon (handoff 5)" do
    strip

    html = rendered_content
    assert_no_match(/#[0-9a-f]{3,8}\b|rgb\(|hsl\(|oklch\(/i, html.gsub(/&#\d+;/, ""))
    assert_no_selector "svg"
    assert_no_match(/\block\b/i, html)
  end

  test "the slot id of a block, the page settings and a post" do
    assert_equal "block-#{@block.id}-hold", Admin::EditorScreen::HoldStripComponent.slot_id(@block)
    assert_equal "page-hold", Admin::EditorScreen::HoldStripComponent.slot_id(@page)
    assert_equal "editor-notice", Admin::EditorScreen::HoldStripComponent.slot_id(@post)
  end

  test "an unknown kind is refused" do
    assert_raises(ArgumentError) { Admin::EditorScreen::HoldStripComponent.new(subject: @block, hold: nil, viewer: @olga, kind: :nope) }
  end

  test "a lost strip for the viewer's own other tab says so in one sentence, for a block, a post and the settings" do
    [ @block, @post, @page ].each do |subject|
      strip(subject: subject, hold: hold_by(@olga), viewer: @olga, kind: :lost)
      assert_selector "[role=alert]", text: "You're editing this in another tab. Your changes weren't saved."
      assert_no_text "Olga Braun is editing"
    end

    strip(kind: :lost)
    assert_selector "[role=alert]", text: "Dana Weiss is editing this block. Your changes weren't saved."
  end
end
