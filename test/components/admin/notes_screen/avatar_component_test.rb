require "test_helper"

class Admin::NotesScreen::AvatarComponentTest < ViewComponent::TestCase
  test "two initials from a name or from one word; the viewer's own is filled, and it is hidden from a screen reader" do
    dana = users(:two).tap { |user| user.update!(name: "Dana van Weiss") }

    render_inline(Admin::NotesScreen::AvatarComponent.new(user: dana, user_id: dana.id, viewer: dana, size: :message))
    assert_selector "span.bg-people.rounded-full[aria-hidden=true]", text: "Dv"

    render_inline(Admin::NotesScreen::AvatarComponent.new(user: users(:reader), user_id: users(:reader).id, viewer: dana, size: :row))
    assert_selector "span.bg-people-tint", text: "re"
    assert_no_selector "span.bg-people"
  end

  test "a deleted user is the empty circle: a hairline on the surface, no letters and no people colour" do
    render_inline(Admin::NotesScreen::AvatarComponent.new(user: nil, user_id: 424242, viewer: users(:two), size: :row))

    assert_selector "span.rounded-full.border.border-field-line.bg-surface[aria-hidden=true]", exact_text: ""
    assert_no_selector "span.bg-people, span.bg-people-tint, span.text-people"
  end
end
