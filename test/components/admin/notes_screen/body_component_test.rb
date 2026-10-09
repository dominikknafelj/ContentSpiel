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

  # The handoff's decision 5.
  test "a link is accent and underlined; a mention is a chip, sunken for somebody else and accent only for the viewer" do
    dana = users(:two).tap { |user| user.update!(name: "Dana") }
    sam = users(:reader).tap { |user| user.update!(name: "Sam") }
    body = "@[#{dana.id}] and @[#{sam.id}]: https://example.com"

    render_inline(Admin::NotesScreen::BodyComponent.new(body: body, users: { dana.id => dana, sam.id => sam }, viewer_id: sam.id))

    assert_selector "a.text-accent.underline[class~='underline-offset-[3px]'][class~='hover:text-accent-hover']", text: "https://example.com"
    assert_selector "[data-note-mention=other].rounded-cs.bg-sunken.text-ink.font-medium[class~='px-0.5']", text: "@Dana", count: 1
    assert_selector "[data-note-mention=viewer].rounded-cs.bg-accent-tint.text-accent.font-medium[class~='px-0.5']", text: "@Sam", count: 1
    assert_no_selector "[data-note-mention=other].text-accent"

    # Without a viewer nobody is "you".
    render_inline(Admin::NotesScreen::BodyComponent.new(body: body, users: { dana.id => dana, sam.id => sam }))
    assert_selector "[data-note-mention=other]", count: 2
    assert_no_selector "[data-note-mention=viewer]"
  end

  test "a mention of a user who is gone reads as a deleted user" do
    render_inline(Admin::NotesScreen::BodyComponent.new(body: "Ask @[424242]", users: {}))

    assert_selector "[data-note-mention]", text: "@a deleted user"
  end
end
