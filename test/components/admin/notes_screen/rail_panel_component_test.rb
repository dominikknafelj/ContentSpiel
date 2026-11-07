require "test_helper"

# The Notes tab of the editors' rail, registered at `editor.rail.tabs`: what it
# answers the slot, and the panel's markup, the notes frame inside it.
class Admin::NotesScreen::RailPanelComponentTest < ViewComponent::TestCase
  include ContentHelper

  def panel(record, viewer: users(:one), **context) = Admin::NotesScreen::RailPanelComponent.new(record: record, viewer: viewer, **context)

  test "it answers the slot: the key, the label, the open count from the screen's reads, and render? for a page or a post" do
    page = create_page(title: "Pricing")
    as(users(:two)) { 2.times { Notes::Start.call(page, body: "A note") } }

    component = panel(page, reads: {})
    assert_equal "notes", component.tab_key
    assert_equal "Notes", component.tab_label
    assert_equal 2, component.tab_count
    assert_equal({ "admin--notes--drawer-target": "total" }, component.tab_count_data)
    assert component.render?
    assert panel(create_post(title: "Hello")).render?
    assert_not panel(Page.new).render?
    assert_not panel(create_media_asset).render?
  end

  test "the header's button and the tab read the counts once between them, through the screen's reads" do
    page = create_page(title: "Pricing")
    as(users(:two)) { Notes::Start.call(page, body: "A note") }
    reads = {}
    viewer = users(:one)

    first = capture_sql { panel(page, viewer: viewer, reads: reads).tab_count }
    second = capture_sql { Admin::NotesScreen::CountsComponent.read(page, viewer: viewer, reads: reads) }

    assert_equal 2, first.size, "the counts and what is unread: two statements"
    assert_empty second
  end

  test "without the screen's reads (a save's stream) it reads nothing and answers a hidden zero" do
    page = create_page(title: "Pricing")
    as(users(:two)) { Notes::Start.call(page, body: "A note") }

    component = panel(page)

    assert_empty capture_sql { assert_equal 0, component.tab_count }
  end

  test "the panel: the notes frame, empty until asked, with the address it opens on and the counts, outside every form" do
    page = create_page(title: "Pricing")
    thread = as(users(:two)) { Notes::Start.call(page, body: "A note") }.record

    as(users(:one)) { render_inline panel(page, reads: {}, query: { "notes" => "open", "thread" => thread.id.to_s }, locale: "en") }

    assert_selector "div#notes-drawer.admin-notes-drawer[role=region][aria-label=Notes][tabindex='-1'][data-admin--notes--drawer-target=drawer]" \
                    "[data-admin--notes--live-target=record][data-open-on-load=true][data-thread='#{thread.id}'][data-key='Page-#{page.id}']" \
                    "[data-action='keydown.esc->admin--notes--drawer#close']"
    assert_selector "#notes-drawer turbo-frame#notes[data-admin--notes--drawer-target=frame]:not([src])"
    assert_selector "#notes-drawer > header button.admin-notes-drawer__back", text: "Back to Pricing"
    assert_selector "#notes-drawer > header button.admin-notes-drawer__close[aria-label=Close]"
    assert_selector "#notes-drawer span#notes-counts[data-counts]", visible: :all
    assert_no_selector "form", wait: 0
  end

  test "a thread that is not a number does not travel, and without notes=open nothing opens on load" do
    as(users(:one)) { render_inline panel(create_page(title: "Pricing"), query: { "thread" => "3/../x" }) }

    assert_selector "#notes-drawer[data-open-on-load=false]"
    assert_no_selector "#notes-drawer[data-thread]", wait: 0
  end
end
