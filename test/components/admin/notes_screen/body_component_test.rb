require "test_helper"

class Admin::NotesScreen::BodyComponentTest < ViewComponent::TestCase
  test "text is escaped, a mention reads as the user's name, a link is a link that leaves the tab" do
    dana = users(:two).tap { |user| user.update!(name: "Dana") }

    render_inline(Admin::NotesScreen::BodyComponent.new(body: "Ask @[#{dana.id}] <b>now</b>: https://example.com/a.", users: { dana.id => dana }))

    assert_selector "[data-note-mention]", text: "@Dana"
    assert_no_selector "b"
    assert_text "<b>now</b>"
    assert_selector "a[href='https://example.com/a'][target=_blank][rel='noopener noreferrer']", text: "https://example.com/a"
  end

  test "a mention of a user who is gone reads as a deleted user" do
    render_inline(Admin::NotesScreen::BodyComponent.new(body: "Ask @[424242]", users: {}))

    assert_selector "[data-note-mention]", text: "@a deleted user"
  end
end
