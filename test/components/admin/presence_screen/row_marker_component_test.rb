require "test_helper"

# The marker of a row in a list: the circles of whoever else is working on
# that record, then "+N". Its element is always there, hidden at nobody, so
# the list's script (`admin--presence--list`) can change it in place.
class Admin::PresenceScreen::RowMarkerComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @record = create_page(title: "Pricing")
    @viewer = users(:one)
    @dana = users(:two).tap { |user| user.update!(name: "Dana Weiss") }
    @reader = users(:reader).tap { |user| user.update!(name: nil) }
  end

  def here(*users, count: users.size) = Presence::Roster::Here.new(count:, users:)

  def render_marker(data, record: @record, viewer: @viewer, **options)
    render_inline(Admin::PresenceScreen::RowMarkerComponent.new(record:, viewer:, data:, **options))
  end

  def marker = "span[data-presence-marker='page-#{@record.id}']"

  def tip = "#{marker} > [data-tooltip]"

  test "nobody here: the element is there, hidden and empty, with its slots, for the script to fill" do
    render_marker(nil)

    assert_selector "#{marker}[hidden][data-presence-id='#{@record.id}'][data-presence-count='0'][data-admin--presence--list-target=marker]", count: 1, visible: :all
    assert_selector "#{marker} > [data-presence-avatar][hidden]", count: 2, visible: :all
    assert_selector "#{marker} > span.sr-only[data-presence-marker-label][data-presence-lead='']", text: "", exact_text: true, visible: :all
    assert_selector "#{tip}[hidden]", text: "", exact_text: true, visible: :all
  end

  test "one person here: their circle alone, named for them, and the tooltip says the same words" do
    render_marker(here(@dana))

    assert_selector "#{marker}:not([hidden])[data-presence-count='1']"
    assert_selector "#{marker} > [data-presence-avatar]:not([hidden]) > span.size-\\[22px\\]", text: "DW", exact_text: true, count: 1
    assert_no_selector "#{marker} svg", visible: :all
    assert_no_selector "#{marker} [data-presence-marker-count]", visible: :all
    assert_selector "#{marker} > span.sr-only[data-presence-marker-label]", text: "Dana Weiss is here", exact_text: true
    assert_selector "#{tip}[hidden][aria-hidden=true]", text: "Dana Weiss is here", exact_text: true, visible: :all
    # The shared tooltip's host, for the pointer; no Tab stop of its own, no
    # `title`, nothing announced.
    assert_equal "admin--ui--tooltip", page.find(marker)["data-controller"]
    assert_no_selector "#{marker}[tabindex], #{marker} [tabindex], [title], [aria-live], [role=status], a, button", visible: :all
  end

  test "two people here: both circles, the narrow +N counting past the first, and the names said in order" do
    render_marker(here(@reader, @dana))

    assert_selector "#{marker}[data-presence-count='2']"
    assert_selector "#{marker} > [data-presence-avatar]:not([hidden]) > span", count: 2
    assert_selector "#{marker} > [data-presence-avatar]:nth-of-type(1) > span", text: "re", exact_text: true
    assert_selector "#{marker} > [data-presence-avatar]:nth-of-type(2) > span", text: "DW", exact_text: true
    assert_selector "#{marker} > [data-presence-more-narrow]:not([hidden])", text: "+1", exact_text: true
    assert_selector "#{marker} > [data-presence-more][hidden]", visible: :all
    assert_selector "#{marker} [data-presence-marker-label]", text: "2 people here: reader, Dana Weiss", exact_text: true
    assert_selector tip, text: "2 people here: reader, Dana Weiss", exact_text: true, visible: :all
  end

  test "more people than circles: the rest are +N, and the texts say how many more" do
    people = Array.new(5) { |i| User.create!(name: "Person #{i}", email_address: "person#{i}@example.com", password: "a-long-password-1") }

    render_marker(here(*people, count: 7))

    assert_selector "#{marker} > [data-presence-avatar]:not([hidden])", count: 2
    assert_selector "#{marker} > [data-presence-more]:not([hidden])", text: "+5", exact_text: true
    assert_selector "#{marker} > [data-presence-more-narrow]:not([hidden])", text: "+6", exact_text: true
    assert_selector "#{marker} [data-presence-marker-label]", text: "7 people here: Person 0, Person 1, Person 2, Person 3, Person 4 and 2 more", exact_text: true
    assert_selector tip, text: "7 people here: Person 0, Person 1, Person 2, Person 3, Person 4 and 2 more", exact_text: true, visible: :all
  end

  test "a row of the posts list has room for three circles" do
    post_record = create_post(title: "Three")

    render_marker(here(@reader, @dana), record: post_record, shown: 3)

    assert_selector "span[data-presence-marker='post-#{post_record.id}'] > [data-presence-avatar]", count: 3, visible: :all
    assert_selector "span[data-presence-marker='post-#{post_record.id}'] > [data-presence-avatar][hidden]", count: 1, visible: :all
  end

  test "inside a link the marker's words follow the link's own after a comma" do
    post_record = create_post(title: "Translating Everything With Mobility")

    render_marker(here(@reader, @dana), record: post_record, joined: true)

    assert_selector "span[data-presence-marker='post-#{post_record.id}'] > span.sr-only[data-presence-marker-label][data-presence-lead=', ']", text: ", 2 people here: reader, Dana Weiss", exact_text: true
    # The tooltip is no part of the link's name: it has the words without the comma.
    assert_selector "span[data-presence-marker='post-#{post_record.id}'] > [data-tooltip]", text: "2 people here: reader, Dana Weiss", exact_text: true, visible: :all
    # Nobody: the comma is not said either.
    render_marker(nil, record: post_record, joined: true)
    assert_selector "span[data-presence-marker='post-#{post_record.id}'] > [data-presence-marker-label][data-presence-lead=', ']", text: "", exact_text: true, visible: :all
    # Nothing interactive in what stands inside a link.
    assert_no_selector "a, button, [tabindex], [role]", visible: :all
  end

  test "a name is text, whatever was typed as one" do
    @dana.update!(name: "<b>Dana</b>")

    render_marker(here(@dana))

    assert_no_selector "b", visible: :all
    assert_selector "#{marker} [data-presence-marker-label]", text: "<b>Dana</b> is here", exact_text: true
  end

  test "words carry the named people's initials beside the count and the label" do
    assert_equal({ count: 0, label: "", initials: [] }, Admin::PresenceScreen::RowMarkerComponent.words(nil))
    assert_equal({ count: 2, label: "2 people here: reader, Dana Weiss", initials: %w[re DW] },
      Admin::PresenceScreen::RowMarkerComponent.words(here(@reader, @dana)))
  end

  test "it takes what the hosts hand every slot component and ignores it; an actor that is no user and a record that is no kind get no marker" do
    render_marker(here(@dana), locale: "en", url_options: {}, counts: {})
    assert_selector marker

    render_marker(here(@dana), viewer: nil)
    assert_no_selector "[data-presence-marker]", visible: :all
    render_marker(here(@dana), record: Tag.new)
    assert_no_selector "[data-presence-marker]", visible: :all
  end

  test "the loader reads who is here once for all the rows, and nothing for no rows or for an actor that is no user" do
    pages = Array.new(3) { |i| create_page(title: "Page #{i}") }
    pages.each { |each| Presence::Mark.arrive(user: @dana, record: each, tab: "tab-12345678") }
    loader = Admin::PresenceScreen::RowMarkerComponent.loader("page")

    data = nil
    statements = capture_sql { data = loader.call(pages + [ @record ], viewer: @viewer) }

    assert_equal 2, statements.size
    assert_equal pages.map(&:id).sort, data.keys.sort
    assert_equal [ @dana ], data[pages.first.id].users
    assert_equal [], capture_sql { assert_equal({}, loader.call([], viewer: @viewer)) }
    assert_equal [], capture_sql { assert_equal({}, loader.call(pages, viewer: nil)) }
  end

  test "it is registered last among the tree's markers, and in the posts list's title line as part of the link" do
    tree = Admin::Slots.entries("tree.row.markers")
    assert_equal [ Admin::NotesScreen::RowPillComponent, Admin::PresenceScreen::RowMarkerComponent ], tree.map(&:component)
    assert tree.last.loader
    assert_equal({ shown: 2 }, tree.last.options)
    title = Admin::Slots.entries("posts.row.title")
    assert_equal [ Admin::PresenceScreen::RowMarkerComponent ], title.map(&:component)
    assert_equal({ joined: true, shown: 3 }, title.first.options)
    assert title.first.loader
  end
end
