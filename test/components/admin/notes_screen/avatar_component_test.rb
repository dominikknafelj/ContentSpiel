require "test_helper"

class Admin::NotesScreen::AvatarComponentTest < ViewComponent::TestCase
  test "two initials from a name, one from an email; the viewer's own is filled, and it is hidden from a screen reader" do
    dana = users(:two).tap { |user| user.update!(name: "Dana van Weiss") }

    render_inline(Admin::NotesScreen::AvatarComponent.new(user: dana, user_id: dana.id, viewer: dana, size: :message))
    assert_selector "span.bg-ink.rounded-full[aria-hidden=true]", text: "Dv"

    render_inline(Admin::NotesScreen::AvatarComponent.new(user: users(:reader), user_id: users(:reader).id, viewer: dana, size: :row))
    assert_selector "span.bg-sunken", text: "r"
    assert_no_selector "span.bg-ink"
  end

  test "a deleted user still gets an avatar" do
    render_inline(Admin::NotesScreen::AvatarComponent.new(user: nil, user_id: 424242, viewer: users(:two), size: :row))

    assert_selector "span.bg-sunken", text: "ad"
  end
end
