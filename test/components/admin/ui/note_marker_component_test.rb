require "test_helper"

# The people bubble: a count of open notes on a row, a tile or a card's
# head. It knows no feature, so every word and number is its caller's.
class Admin::Ui::NoteMarkerComponentTest < ViewComponent::TestCase
  test "read is the people bubble with the outline glyph and the count" do
    render_inline Admin::Ui::NoteMarkerComponent.new(count: 2, label: "2 open notes")

    assert_selector ".admin-notes-marker[data-has-notes]:not([data-unread])", text: "2"
    assert_selector ".admin-notes-marker svg[class~='size-3']", count: 1
    assert_no_text "new"
    assert_no_selector ".admin-notes-marker--small"
    assert_no_selector ".admin-notes-marker--on-image"
  end

  test "unread is the accent bubble with the filled glyph and says 3 new" do
    render_inline Admin::Ui::NoteMarkerComponent.new(count: 3, label: "3 open notes, new for you", unread: true)

    assert_selector ".admin-notes-marker[data-has-notes][data-unread]", text: "3 new"
    assert_selector ".admin-notes-marker svg path[fill=currentColor], .admin-notes-marker svg[fill=currentColor]"
    assert_selector ".admin-notes-marker[aria-label='3 open notes, new for you']"
  end

  test "with an address it is a link named by its label, without one an image, or hidden where its row's link names it" do
    render_inline Admin::Ui::NoteMarkerComponent.new(count: 1, label: "1 open note", href: "/cs-studio/posts/1?notes=open", data: { notes_count: true })
    assert_selector "a.admin-notes-marker.no-underline[href='/cs-studio/posts/1?notes=open'][aria-label='1 open note'][data-has-notes][data-notes-count][data-turbo-prefetch=false]"
    assert_no_selector ".admin-notes-marker--readonly"

    render_inline Admin::Ui::NoteMarkerComponent.new(count: 1, label: "1 open note", size: :small)
    assert_selector "span.admin-notes-marker.admin-notes-marker--readonly.admin-notes-marker--small[role=img][aria-label='1 open note'][title='1 open note'][data-has-notes]"

    render_inline Admin::Ui::NoteMarkerComponent.new(count: 1, label: "1 open note", aria_hidden: true, id: "row-count")
    assert_selector "span#row-count.admin-notes-marker--readonly[aria-hidden=true][aria-label='1 open note']", visible: :all
    assert_no_selector "span[role=img]", visible: :all
  end

  test "on an image it keeps the surface ring" do
    render_inline Admin::Ui::NoteMarkerComponent.new(count: 1, label: "1 open note", on_image: true)

    assert_selector ".admin-notes-marker.admin-notes-marker--on-image"
  end

  test "an unknown size is refused" do
    assert_raises(ArgumentError) { Admin::Ui::NoteMarkerComponent.new(count: 1, label: "x", size: :huge) }
  end

  test "nothing at a count of 0" do
    render_inline Admin::Ui::NoteMarkerComponent.new(count: 0, label: "No notes")

    assert_equal "", rendered_content
  end
end
