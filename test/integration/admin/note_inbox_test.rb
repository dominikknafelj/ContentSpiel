require "test_helper"

class Admin::NoteInboxTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    users(:two).update!(name: "Dana")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Ready, @[#{users(:reader).id}]?") }.record
    sign_in_as(users(:reader))
  end

  test "the dashboard has Notes for you and Waiting for you, each in a frame of its own, and the sidebar counts the unread" do
    get "/cs-studio"

    assert_select "turbo-frame#notes-for-you section.admin-dashboard-panel--action[aria-labelledby=dashboard-notes-for-you]" do
      assert_select "header h2", "Notes for you"
      assert_select "header .admin-dashboard-panel__line", "Mentions and replies addressed to you."
      # The whole row is one link, with the row's hover.
      assert_select "li > a[data-delivery][data-unread][href='/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}'][data-turbo-frame=_top][class~='hover:bg-paper']", count: 1 do
        assert_select "[data-inbox-sentence]", text: "Dana mentioned you"
        assert_select "[data-inbox-excerpt]", text: /Ready, @reader\?/
        assert_select "[data-inbox-where]", text: "Page · Pricing"
      end
      assert_select "li a a", count: 0
      # "All notes for you →" in words at the foot of the panel, not an
      # arrow in its head.
      assert_select "footer a[href='/cs-studio/notes'][data-turbo-frame=_top]", text: "All notes for you →"
      assert_select "header a", count: 0
      # Unread is said in words too, and counted in the card's header.
      assert_select "[data-delivery][data-unread] [data-inbox-new]", text: "New"
      assert_select "[data-delivery] .sr-only", count: 0
      assert_select "header [data-notes-new]", text: "1 new"
    end
    assert_select "turbo-frame#dashboard-waiting section.admin-dashboard-panel--action[aria-labelledby=dashboard-waiting-title]" do
      assert_select "header h2", "Waiting for you"
      assert_select "li > .admin-waiting-row", count: 1 do
        assert_select "a.admin-waiting-row__link[href='/cs-studio/pages/#{@page.id}?notes=open'][data-turbo-frame=_top]", text: "Pricing"
        assert_select ".admin-notes-marker[data-has-notes]:not([data-unread])", text: "1"
        assert_select ".admin-row-verb", text: "Open thread"
      end
    end
    assert_select "#sidebar #sidebar-badge-dashboard:not([hidden])", text: "1"
  end

  test "a note on a block says which, and a read row says nothing in accent" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:two)) { Notes::Start.call(block, body: "This one, @[#{users(:reader).id}]") }
    as(users(:reader)) { Notes::MarkRead.call }

    get "/cs-studio"

    assert_select "turbo-frame#notes-for-you" do
      assert_select "[data-delivery]", count: 2
      assert_select "[data-delivery][data-unread]", count: 0
      # The block as the list's group heading names it: its type, then --
      # it is empty -- its place on the page.
      assert_select "[data-inbox-where]", text: "Page · Pricing · Rich text · Block 1"
      assert_select "[class*=accent]", count: 0
      assert_select "[data-notes-new]", count: 0
      assert_select "form[action='/cs-studio/notes/read']", count: 0
    end
    assert_select "#sidebar-badge-dashboard[hidden]", text: ""
  end

  test "each part is fetched on its own" do
    get "/cs-studio/notes/card"
    assert_select "turbo-frame#notes-for-you [data-delivery]", count: 1
    assert_select "#sidebar", count: 0

    get "/cs-studio/notes/unread"
    assert_equal({ "unread" => 1 }, response.parsed_body)
  end

  test "the full list pages by 50 and Mark all read reads everything" do
    as(users(:two)) { 51.times { |index| Notes::Start.call(@page, body: "Note #{index} for @[#{users(:reader).id}]") } }

    get "/cs-studio/notes"
    assert_select "h1", text: "Notes for you"
    assert_select "[data-delivery]", count: 50
    get "/cs-studio/notes", params: { page: 2 }
    assert_select "[data-delivery]", count: 2

    post "/cs-studio/notes/read"
    assert_redirected_to "/cs-studio/notes"
    assert_equal 0, Notes::Delivery.unread.where(user: users(:reader)).count
    follow_redirect!
    assert_select "[data-delivery][data-unread]", count: 0
    assert_select "#sidebar-badge-dashboard[hidden]"
    assert_select "form[action='/cs-studio/notes/read']", count: 0
  end

  test "the filter's tabs carry their counts, a count of 0 included, and the shown scope is the current tab" do
    get "/cs-studio/notes"

    assert_select "nav[aria-label=Show] a", count: 3
    assert_select "nav[aria-label=Show] a[href='/cs-studio/notes'][aria-current=page]", text: /All\s+1/
    assert_select "nav[aria-label=Show] a[href='/cs-studio/notes?show=unread']:not([aria-current])[data-turbo-prefetch=false]", text: /Unread\s+1/
    assert_select "nav[aria-label=Show] a[href='/cs-studio/notes?show=mentions']", text: /Mentions\s+1/

    as(users(:reader)) { Notes::MarkRead.call }
    get "/cs-studio/notes", params: { show: "unread" }

    assert_select "nav[aria-label=Show] a[aria-current=page]", count: 1
    assert_select "nav[aria-label=Show] a[href='/cs-studio/notes?show=unread'][aria-current=page]", text: /Unread\s+0/
    assert_select "nav[aria-label=Show] a[href='/cs-studio/notes'] .text-count", text: "1"
  end

  test "each scope lists its own deliveries" do
    as(users(:two)) { Notes::Resolve.call(@thread) }
    as(users(:reader)) { Notes::MarkRead.call }
    other = as(users(:two)) { Notes::Start.call(create_post(title: "Hello"), body: "Look, @[#{users(:reader).id}]") }.record
    as(users(:two)) { Notes::Resolve.call(other) }

    get "/cs-studio/notes", params: { show: "mentions" }
    assert_select "[data-delivery]", count: 0

    get "/cs-studio/notes", params: { show: "unread" }
    assert_select "[data-delivery]", count: 1
  end

  test "an unknown show is All" do
    get "/cs-studio/notes", params: { show: "everything" }

    assert_response :ok
    assert_select "[data-delivery]", count: 1
    assert_select "nav[aria-label=Show] a[aria-current=page]", text: /All/
  end

  test "a page beyond the last under a scope says so and goes back to that scope's first page, and the pager keeps the scope" do
    get "/cs-studio/notes", params: { show: "unread", page: 9 }
    assert_select "a[href='/cs-studio/notes?show=unread']", text: "Back to page 1"

    get "/cs-studio/notes", params: { page: 9 }
    assert_select "a[href='/cs-studio/notes']", text: "Back to page 1"

    as(users(:two)) { 51.times { |index| Notes::Start.call(@page, body: "Note #{index} for @[#{users(:reader).id}]") } }
    get "/cs-studio/notes", params: { show: "mentions" }
    assert_select "nav a[href*='show=mentions'][href*='page=2']"
    get "/cs-studio/notes", params: { show: "mentions", page: 2 }
    assert_select "[data-delivery]", count: 2
  end

  test "each scope's empty list says its own sentence" do
    as(users(:reader)) { Notes::MarkRead.call }

    get "/cs-studio/notes", params: { show: "unread" }
    assert_select ".admin-empty-state", text: "No unread notes"
    as(users(:two)) { Notes::Resolve.call(@thread) }
    as(users(:reader)) { Notes::MarkRead.call }
    get "/cs-studio/notes", params: { show: "mentions" }
    assert_select ".admin-empty-state", text: "No mentions yet"

    sign_in_as(users(:one))
    get "/cs-studio/notes"
    assert_select ".admin-empty-state", text: /Nothing for you yet\s+When someone mentions you or replies to you, it shows here\./
    assert_select ".admin-empty-state a, .admin-empty-state button", count: 0
  end

  test "Mark all read is a small secondary, shown only while something is unread, and the screen draws no primary" do
    get "/cs-studio/notes"
    small_secondary = Admin::Ui::ButtonComponent.classes(:secondary, size: :small).split.map { |name| "[class~='#{name}']" }.join
    assert_select "form[action='/cs-studio/notes/read'] button#{small_secondary}", text: "Mark all read"
    assert_select "main [class~='text-on-accent']", count: 0

    as(users(:reader)) { Notes::MarkRead.call }
    get "/cs-studio/notes"
    assert_select "form[action='/cs-studio/notes/read']", count: 0
  end

  test "the screen is the lists' rail: heading row, then the filter, the list and the rail of open threads in that order, the rail a link per record" do
    get "/cs-studio/notes"

    assert_select ".admin-list-rail > .admin-list-rail__head h1", text: "Notes for you"
    assert_select ".admin-list-rail__grid > :nth-child(1)[class~=flex]", count: 1
    assert_select ".admin-list-rail__grid > :nth-child(1) [aria-label='Show']", count: 1
    assert_select ".admin-list-rail__grid > :nth-child(2) [data-delivery]", count: 1
    assert_select ".admin-list-rail__grid > section.admin-list-rail__rail.admin-notes-threads:nth-child(3)[aria-labelledby=open-threads-heading]", count: 1
    assert_select ".admin-notes-threads h2#open-threads-heading", text: "Open threads"
    assert_select ".admin-notes-threads li a[href='/cs-studio/pages/#{@page.id}?notes=open'][data-turbo-prefetch=false][data-turbo-frame=_top]", text: /Pricing\s+1 note · /
    assert_no_match "max-w-[880px]", response.body
    assert_no_match "more on other pages", response.body

    get "/cs-studio/notes", params: { show: "mentions" }
    assert_select ".admin-notes-threads li", count: 1

    as(users(:two)) { Notes::Resolve.call(@thread) }
    get "/cs-studio/notes"
    assert_select ".admin-notes-threads li", count: 0
    assert_select ".admin-notes-threads", text: /No open threads\./
  end

  test "Mark all read on the dashboard's card comes back to the dashboard" do
    get "/cs-studio"
    assert_select "turbo-frame#notes-for-you form[action='/cs-studio/notes/read?back=dashboard'][data-turbo-frame=_top] button", text: "Mark all read"

    post "/cs-studio/notes/read", params: { back: "dashboard" }

    assert_redirected_to "/cs-studio"
    assert_equal 0, Notes::Delivery.unread.where(user: users(:reader)).count
  end

  # "Mark all read" reads every unread delivery of the person's, the ones
  # hidden at that moment included.
  test "Mark all read also reads what is hidden at that moment" do
    post_record = create_post(title: "Hidden")
    as(users(:two)) { Notes::Start.call(post_record, body: "For @[#{users(:reader).id}]") }
    post_record.update!(trashed_at: Time.current)
    get "/cs-studio/notes/unread"
    assert_equal({ "unread" => 1 }, response.parsed_body)

    post "/cs-studio/notes/read"

    assert_equal 0, Notes::Delivery.unread.where(user: users(:reader)).count
  end

  test "following the row marks it read, because opening the thread does" do
    get "/cs-studio/notes/page/#{@page.id}/threads/#{@thread.id}", headers: { "Turbo-Frame" => "notes" }

    get "/cs-studio/notes/unread"
    assert_equal({ "unread" => 0 }, response.parsed_body)
  end

  # The row's own link is the editor: fetching it (a hover's prefetch, a
  # crawler) reads nothing. Only the thread's own view marks it read.
  test "opening the editor the row links to does not mark the delivery read by itself" do
    get "/cs-studio/pages/#{@page.id}", params: { notes: "open", thread: @thread.id }
    assert_response :ok

    get "/cs-studio/notes/unread"
    assert_equal({ "unread" => 1 }, response.parsed_body)
  end

  test "an empty inbox says so, and someone with no rights sees nothing of anyone's" do
    sign_in_as(User.create!(email_address: "stranger@example.com", password: "password-password"))

    get "/cs-studio"

    assert_select "turbo-frame#notes-for-you", text: /No notes for you/
    assert_select "turbo-frame#dashboard-waiting", text: /Nothing is waiting for you/
    assert_select "#sidebar-badge-dashboard[hidden]"
    assert_no_match "Pricing", response.body

    get "/cs-studio/notes"
    assert_select "[data-delivery]", count: 0
    assert_select "main", text: /Nothing for you yet/
  end

  test "a page beyond the last says so, and the inbox needs a sign-in" do
    get "/cs-studio/notes", params: { page: 9 }
    assert_response :ok
    assert_select "[data-delivery]", count: 0

    delete "/cs-studio/sign-out"
    [ "/cs-studio/notes", "/cs-studio/notes/card", "/cs-studio/notes/unread", "/cs-studio/dashboard/waiting" ].each do |path|
      get path
      assert_response :redirect, path
    end
  end

  # The sidebar is on every CS Studio page, so its count is paid on every
  # page load: one COUNT on `note_deliveries`, narrowed by the read scope, and
  # nothing else of notes on a screen that shows none.
  test "a page load pays exactly one statement for the sidebar's unread count, whatever the number of notes" do
    paths = [ "/cs-studio/tags", "/cs-studio/api_tokens", "/cs-studio/account" ]
    sign_in_as(users(:two))
    as(users(:one)) { Notes::Start.call(@page, body: "For @[#{users(:two).id}]") }
    paths.each { |path| get path } # warm-up
    note_statements = ->(path) { capture_sql { get path }.grep(/"note_/) }

    paths.each do |path|
      statements = note_statements.call(path)
      assert_response :ok, path
      assert_equal 1, statements.size, path
      assert_match(/\ASELECT COUNT\(\*\) FROM "note_deliveries" WHERE "note_deliveries"."user_id" = \S+ AND .*"read_at" IS NULL/m, statements.first)
      assert_select "#sidebar-badge-dashboard", text: "1"
    end

    as(users(:one)) { 5.times { |index| Notes::Start.call(create_post(title: "More #{index}"), body: "For @[#{users(:two).id}]") } }
    paths.each { |path| assert_equal 1, note_statements.call(path).size, path }
    assert_select "#sidebar-badge-dashboard", text: "6"
  end

  # A frame's own answer renders no layout, so no sidebar and no count.
  test "an answer without the layout pays nothing for the sidebar" do
    assert_empty capture_sql { get "/cs-studio/dashboard/waiting", headers: { "Turbo-Frame" => "dashboard-waiting" } }.grep(/"note_deliveries"/)
  end

  test "the dashboard reads its notes in the same statements with one note or many" do
    get "/cs-studio"
    few = capture_sql { get "/cs-studio" }.grep(/"note_/).size

    as(users(:two)) do
      6.times { |index| Notes::Start.call(create_page(title: "Page #{index}"), body: "For @[#{users(:reader).id}]") }
    end
    get "/cs-studio"

    assert_equal few, capture_sql { get "/cs-studio" }.grep(/"note_/).size
  end

  test "one delivery as data, for the toast and the desktop notification: mine only" do
    delivery = Notes::Delivery.find_by!(user: users(:reader))

    get "/cs-studio/notes/deliveries/#{delivery.id}"

    assert_equal({ "id" => delivery.id, "reason" => "mention", "sentence" => "Dana mentioned you", "title" => "Pricing",
      "excerpt" => "Ready, @reader?", "url" => "/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}", "thread_id" => @thread.id }, response.parsed_body)

    sign_in_as(users(:two))
    get "/cs-studio/notes/deliveries/#{delivery.id}"
    assert_response :not_found
  end

  # The scoped fetch behind the toast (the person's signal says nothing): a
  # delivery on a record the person has lost the right to read, one in the trash and
  # an id that names nothing are the same 404, and none of them says which.
  test "a delivery on a record the person may not read any more is not found, like one that is not there" do
    delivery = Notes::Delivery.find_by!(user: users(:reader))

    get "/cs-studio/notes/deliveries/0"
    assert_response :not_found

    @page.update!(trashed_at: Time.current)
    get "/cs-studio/notes/deliveries/#{delivery.id}"
    assert_response :not_found
    assert_no_match(/Pricing|Ready|Dana/, response.body)
  end

  # The sentence is text for `textContent`: a name is written as it is, never
  # as markup and never as entities.
  test "a delivery's sentence names a person as text, and says so when nobody can be named" do
    users(:two).update!(name: "Dana & <b>Co</b>")
    delivery = Notes::Delivery.find_by!(user: users(:reader))

    get "/cs-studio/notes/deliveries/#{delivery.id}"
    assert_equal "Dana & <b>Co</b> mentioned you", response.parsed_body["sentence"]

    as(users(:reader)) { Notes::Reply.call(@thread, body: "Yes") }
    as(users(:two)) { Notes::Resolve.call(@thread) }
    as(users(:two)) { Notes::Reopen.call(@thread) }
    reopened = Notes::Delivery.find_by!(user: users(:reader), reason: "reopened")

    get "/cs-studio/notes/deliveries/#{reopened.id}"
    assert_equal "A note was reopened", response.parsed_body["sentence"]
  end

  # "Mark all read" names the tab that pressed it (`X-Notes-Tab`), as a
  # record's notes requests do: that tab's page is drawn again by the
  # redirect, and its other tabs are told.
  test "Mark all read's signal names the tab whose request it was" do
    stream = Notes::Signals.person_stream(users(:reader).id)

    assert_broadcast_on(stream, { kind: "inbox", origin: "tab-0f8fad5b-d9cb-469f" }) do
      post "/cs-studio/notes/read", headers: { "X-Notes-Tab" => "tab-0f8fad5b-d9cb-469f" }
    end
    as(users(:two)) { Notes::Start.call(@page, body: "Again, @[#{users(:reader).id}]") }
    assert_broadcast_on(stream, { kind: "inbox" }) do
      post "/cs-studio/notes/read", headers: { "X-Notes-Tab" => "Not an id" }
    end
  end
end
