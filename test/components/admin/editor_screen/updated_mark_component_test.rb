require "test_helper"

class Admin::EditorScreen::UpdatedMarkComponentTest < ViewComponent::TestCase
  def mark(user, at: 1.minute.ago)
    render_inline(Admin::EditorScreen::UpdatedMarkComponent.new(change: Editing::LastChange::Change.new(user: user, at: at)))
  end

  test "names the person as notes and presence do, and when" do
    users(:two).update!(name: "Dana Weiss")

    mark(users(:two))

    assert_selector "span[data-editing-mark]", text: /Updated by Dana Weiss · /
    assert_no_selector "[role], [aria-live]"
  end

  test "a user without a name shows the part of the address before the at sign" do
    users(:two).update!(name: nil)

    mark(users(:two))

    assert_selector "[data-editing-mark]", text: /Updated by two · /
  end

  test "a name with markup in it is text" do
    users(:two).update!(name: "<b>Dana</b>")

    mark(users(:two))

    assert_no_selector "[data-editing-mark] b"
    assert_text "Updated by <b>Dana</b>"
  end

  test "the colleague's avatar stands before Updated by" do
    users(:two).update!(name: "Dana Weiss")

    mark(users(:two))

    assert_selector "span[data-editing-mark].text-label.text-meta > span.size-\\[22px\\].bg-people-tint[aria-hidden=true]", text: "DW"
    assert_no_selector "span[data-editing-mark] .inset-ring-people"
    assert_selector "span[data-editing-mark] > span[aria-hidden] + span", text: /Updated by Dana Weiss · /
  end

  test "taken over says Taken over by you · just now, with no avatar" do
    html = render_inline(Admin::EditorScreen::UpdatedMarkComponent.new(taken_over: true))

    assert_selector "span[data-editing-mark]", text: "Taken over by you · just now"
    assert_no_selector "[data-editing-mark] [aria-hidden]"
    assert_no_selector "[role], [aria-live]"
    assert_not_nil html
  end

  test "no change renders nothing" do
    assert_empty render_inline(Admin::EditorScreen::UpdatedMarkComponent.new(change: nil)).to_html.strip
  end
end
