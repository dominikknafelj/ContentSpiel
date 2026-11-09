require "test_helper"

# The open-notes pill of a list row, registered at the `tree.row.markers` and
# `posts.row.markers` slots. It is the shared bubble: the posts list's a link
# to the post's notes, the page tree's a small readonly image.
class Admin::NotesScreen::RowPillComponentTest < ViewComponent::TestCase
  include ContentHelper

  def render_pill(record, data, **context)
    render_inline(Admin::NotesScreen::RowPillComponent.new(record: record, viewer: users(:one), data: data, **context))
  end

  test "a post's pill is the bubble as a link to its notes, a page's the small image, and unread is named new for you" do
    post = create_post(title: "Hello")
    render_pill(post, { open: 1, unread: false }, url_options: {})
    assert_selector "a.admin-notes-marker.no-underline[data-notes-count][data-has-notes][href='/cs-studio/posts/#{post.id}?notes=open'][aria-label='1 open note']", text: "1"
    assert_selector "a.admin-notes-marker svg", count: 1
    assert_no_selector "a.admin-notes-marker--small"
    assert_no_selector "[data-unread]"

    pricing = create_page(title: "Pricing")
    render_pill(pricing, { open: 2, unread: false })
    assert_selector "span.admin-notes-marker.admin-notes-marker--readonly.admin-notes-marker--small[data-notes-marker][data-has-notes][role=img]" \
                    "[title='2 open notes'][aria-label='2 open notes']", text: "2"
    assert_no_selector "[data-unread]"

    render_pill(pricing, { open: 1, unread: true })
    assert_selector "span[data-notes-marker][data-unread][aria-label='1 open note, new for you']", text: "1 new"

    render_pill(post, { open: 3, unread: true }, url_options: {})
    assert_selector "a[data-unread][aria-label='3 open notes, new for you']", text: "3 new"
  end

  test "a post's link keeps the list's language" do
    post = create_post(title: "Hello")
    render_pill(post, { open: 3, unread: true }, url_options: { locale: "de" })

    assert_selector "a[data-notes-count][data-unread][href='/cs-studio/posts/#{post.id}?locale=de&notes=open']"
  end

  test "nothing at zero, and nothing without loaded data" do
    page = create_page(title: "Quiet")

    render_pill(page, { open: 0, unread: false })
    assert_equal "", rendered_content
    render_pill(page, nil)
    assert_equal "", rendered_content
  end

  test "the person a count is unread for is the actor, or an API token's user" do
    token = ApiToken.new(user: users(:two))

    assert_equal users(:one), Notes.user_of(users(:one))
    assert_equal users(:two), Notes.user_of(token)
    assert_nil Notes.user_of(nil)
  end

  test "the loader reads the counts once for all rows, with the viewer, for each record type" do
    one = create_page(title: "One")
    two = create_page(title: "Two")
    as(users(:two)) { Notes::Start.call(one, body: "A note") }
    as(users(:two)) { Notes::Start.call(two, body: "Another") }
    as(users(:two)) { Notes::Resolve.call(Notes::Start.call(two, body: "Done").record) }
    one_unread = Notes::Counts.unread_among("Page", [ one.id, two.id ], users(:one))

    data = Admin::NotesScreen::RowPillComponent.loader("Page").call([ one, two ], viewer: users(:one))

    assert_equal({ one.id => { open: 1, unread: one_unread.include?(one.id) }, two.id => { open: 1, unread: one_unread.include?(two.id) } }, data)
    assert_equal({}, Admin::NotesScreen::RowPillComponent.loader("Post").call([], viewer: users(:one)))
  end
end
