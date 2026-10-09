require "test_helper"

class Admin::NoteInboxTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    users(:two).update!(name: "Dana")
    @thread = as(users(:two)) { Notes::Start.call(@page, body: "Ready, @[#{users(:reader).id}]?") }.record
    sign_in_as(users(:reader))
  end

  test "the dashboard has Notes for you and Open threads, each in a frame of its own, and the sidebar counts the unread" do
    get "/cs-studio"

    assert_select "turbo-frame#notes-for-you section[aria-labelledby=dashboard-notes-for-you]" do
      assert_select "[data-delivery][data-unread] a[href='/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}'][data-turbo-frame=_top]", text: "Dana mentioned you"
      assert_select "p", text: /Ready, @reader@example.com\?/
      assert_select "p", text: /Page · Pricing/
      assert_select "a[href='/cs-studio/notes'][aria-label='All notes for you']"
      # Unread is said in words too, and counted in the card's header.
      assert_select "[data-delivery][data-unread] .sr-only", text: "Unread"
      assert_select "header [data-notes-new]", text: "1 new"
    end
    assert_select "turbo-frame#notes-open-threads section[aria-labelledby=dashboard-open-threads]" do
      assert_select "a[href='/cs-studio/pages/#{@page.id}?notes=open'][data-turbo-frame=_top]", text: "Pricing"
      assert_select "li .admin-notes-marker[data-has-notes]:not([data-unread])", text: "1"
      assert_select "header [data-notes-total]", text: "1"
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
      assert_select "p", text: /Page · Pricing · Rich text/
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

    get "/cs-studio/notes/open_threads"
    assert_select "turbo-frame#notes-open-threads a", text: "Pricing"
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

  test "Mark all read on the dashboard's card comes back to the dashboard" do
    get "/cs-studio"
    assert_select "turbo-frame#notes-for-you form[action='/cs-studio/notes/read?back=dashboard'][data-turbo-frame=_top] button", text: "Mark all read"

    post "/cs-studio/notes/read", params: { back: "dashboard" }

    assert_redirected_to "/cs-studio"
    assert_equal 0, Notes::Delivery.unread.where(user: users(:reader)).count
  end

  # Accepted (the controller's ruling): "Mark all read" reads every unread
  # delivery of the person's, the ones hidden at that moment included.
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
    assert_select "turbo-frame#notes-open-threads", text: /No open threads/
    assert_select "#sidebar-badge-dashboard[hidden]"
    assert_no_match "Pricing", response.body

    get "/cs-studio/notes"
    assert_select "[data-delivery]", count: 0
    assert_select "main", text: /No notes for you/
  end

  test "a page beyond the last says so, and the inbox needs a sign-in" do
    get "/cs-studio/notes", params: { page: 9 }
    assert_response :ok
    assert_select "[data-delivery]", count: 0

    delete "/cs-studio/sign-out"
    [ "/cs-studio/notes", "/cs-studio/notes/card", "/cs-studio/notes/open_threads", "/cs-studio/notes/unread" ].each do |path|
      get path
      assert_response :redirect, path
    end
  end

  # The sidebar is on every CS Studio page, so its count is paid on every
  # page load: one COUNT on `note_deliveries`, narrowed by the read scope, and
  # nothing else of notes on a screen that shows none.
  test "a page load pays exactly one statement for the sidebar's unread count, whatever the number of notes" do
    paths = [ "/cs-studio/tags", "/cs-studio/api_tokens", "/cs-studio/account/password" ]
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
    assert_empty capture_sql { get "/cs-studio/notes/open_threads" }.grep(/"note_deliveries"/)
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
end
