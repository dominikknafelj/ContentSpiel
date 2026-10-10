require "application_system_test_case"

# The inbox in a browser (notes spec §5): the dashboard's two cards, the full
# list and the sidebar's count, and where their rows lead.
class Admin::NoteInboxSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana")
    @me = users(:one)
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    sign_in_via_form(@me)
  end

  # "Open" is remembered in this browser, and the browser is shared with the
  # tests that follow: every notes system test forgets it again.
  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def mention(subject, body = "Is this ready, @[#{@me.id}]?") = as(users(:two)) { Notes::Start.call(subject, body: body) }.record

  def open_dashboard
    visit "/cs-studio"
    await_admin_controllers
  end

  test "a row of Notes for you opens the page with its drawer at the thread, which reads it: the dot, the count and the badge go" do
    thread = mention(@block)
    open_dashboard

    assert_selector "#sidebar-badge-dashboard", text: "1"
    within "turbo-frame#notes-for-you" do
      assert_selector "[data-delivery][data-unread]", count: 1
      assert_selector "header", text: "1 NEW"
      assert_text "Page · Pricing · Rich text"
      press "Dana mentioned you"
    end

    # A whole editor visit and then the drawer's frame: more than the default wait on a busy machine.
    assert_current_path(/\/pages\/#{@page.id}\?notes=open&thread=#{thread.id}\z/, wait: 8)
    assert_selector "#notes-drawer #note-thread-#{thread.id}", text: "Is this ready", wait: 8
    assert_eventually(message: "opening the thread never marked its delivery read") { Notes::Delivery.unread.where(user: @me).none? }

    open_dashboard
    within "turbo-frame#notes-for-you" do
      assert_selector "[data-delivery]", count: 1
      assert_no_selector "[data-delivery][data-unread]"
      assert_no_selector "[data-notes-new]"
      assert_no_button "Mark all read"
    end
    assert_no_selector "#sidebar-badge-dashboard" # in the page, hidden and empty
    assert_selector "#sidebar-badge-dashboard[hidden]", visible: :all
  end

  test "an image's row opens the Media screen with the image chosen and the thread in its panel" do
    asset = create_media_asset
    thread = mention(asset, "Too dark, @[#{@me.id}]")
    open_dashboard

    within("turbo-frame#notes-for-you") { press "Dana mentioned you" }

    assert_current_path(/\/media\?selected=#{asset.id}&thread=#{thread.id}\z/)
    assert_selector "#media-panel #media-notes #note-thread-#{thread.id}", text: "Too dark"
    assert_eventually(message: "opening the thread never marked its delivery read") { Notes::Delivery.unread.where(user: @me).none? }
  end

  test "a row whose thread has since been deleted opens the page's notes with a sentence, not an error" do
    thread = mention(@page)
    kept = mention(@page, "Still here")
    open_dashboard
    assert_selector "turbo-frame#notes-for-you [data-delivery]", count: 1 # "Still here" mentions nobody
    as(users(:two)) { assert Notes::DeleteMessage.call(thread.first_message).ok? }

    find("turbo-frame#notes-for-you a[href$='thread=#{thread.id}']").click

    # The JavaScript error collector fails this test on "Content missing".
    assert_selector "#notes-drawer #notes-list [role=status]", text: "This note is gone"
    assert_selector "#notes-drawer a#note-row-#{kept.id}", text: "Still here"
  end

  test "Mark all read on the card stays on the dashboard and empties the badge" do
    mention(@page)
    mention(@block, "And this, @[#{@me.id}]")
    open_dashboard
    assert_selector "#sidebar-badge-dashboard", text: "2"

    within("turbo-frame#notes-for-you") { press "Mark all read" }

    assert_no_selector "turbo-frame#notes-for-you [data-delivery][data-unread]"
    assert_selector "turbo-frame#notes-for-you [data-delivery]", count: 2
    assert_current_path "/cs-studio"
    assert_no_selector "#sidebar-badge-dashboard"
    assert_equal 0, Notes::Delivery.unread.where(user: @me).count
  end

  test "a row of Notes for you is one link as wide as its card" do
    mention(@page)
    open_dashboard

    widths = page.evaluate_script("[ 'section', 'li > a[data-delivery]' ].map((selector) => document.querySelector('turbo-frame#notes-for-you ' + selector).getBoundingClientRect().width)")
    assert_in_delta widths[0], widths[1], 2
    assert_selector "turbo-frame#notes-for-you footer a", text: "All notes for you →"
  end

  test "Open threads lists a record once with its count in the neutral pill and opens its notes" do
    mention(@page)
    mention(@block)
    open_dashboard

    within "turbo-frame#notes-open-threads" do
      assert_selector "li", count: 1
      assert_selector "li .admin-notes-marker[data-has-notes]:not([data-unread])", text: "2"
      # The whole row is the link: as wide as the card, and it holds the pill.
      widths = page.evaluate_script("[ 'section', 'li > a' ].map((selector) => document.querySelector('turbo-frame#notes-open-threads ' + selector).getBoundingClientRect().width)")
      assert_in_delta widths[0], widths[1], 2
      assert_selector "li > a .admin-notes-marker"
      assert_selector "li > a", text: /Page · Dana · /
      find("li > a").click
    end

    # As above: a visit, then the drawer's frame.
    assert_current_path(/\/pages\/#{@page.id}\?notes=open\z/, wait: 8)
    assert_selector "#notes-drawer #notes-list a[data-note-row]", count: 2, wait: 8
  end

  test "All notes for you is the same rows as a page, and its Mark all read stays there" do
    thread = mention(@page)
    open_dashboard

    # The footer's link, in words (the handoff's footer), not the header's arrow.
    within("turbo-frame#notes-for-you footer") { click_link "All notes for you" }

    assert_current_path "/cs-studio/notes"
    assert_selector "h1", text: "Notes for you"
    assert_selector "a[data-delivery][data-unread][href$='?notes=open&thread=#{thread.id}']", text: "Dana mentioned you"
    # The sidebar's Dashboard entry is not the current one here, and still counts.
    assert_selector "#sidebar-badge-dashboard", text: "1"

    press "Mark all read"

    assert_no_selector "[data-delivery][data-unread]"
    assert_selector "[data-delivery]", count: 1
    assert_current_path "/cs-studio/notes"
    assert_no_selector "#sidebar-badge-dashboard"
    assert_no_button "Mark all read"
  end
end
