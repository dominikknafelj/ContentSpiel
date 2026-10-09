require "test_helper"

# The notes frame, its two views and its parts (notes spec §4.2, plan "Stable
# ids and their endpoints"): each is a GET scoped to a container the viewer
# may read.
class Admin::NotesTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @thread = as(users(:two)) { Notes::Start.call(@block, body: "Is €49 right, @[#{users(:reader).id}]? See https://example.com", quote: "€49 a month") }.record
    @stranger = User.create!(email_address: "stranger@example.com", password: "password-password")
    @base = "/cs-studio/notes/page/#{@page.id}"
  end

  def frame = { "Turbo-Frame" => "notes" }

  test "the list: a row per open thread under its block's group, with the author, the first words, and new for the person it is addressed to" do
    as(users(:one)) { Notes::Reply.call(@thread, body: "Yes") }
    sign_in_as(users(:reader))

    get @base, headers: frame

    assert_response :ok
    assert_select "turbo-frame#notes #notes-list[data-notes-view=list][data-notes-container='Page-#{@page.id}']"
    assert_select "section#notes-group-ContentBlock-#{@block.id} a#note-row-#{@thread.id}[data-note-row][data-unread][href='#{@base}/threads/#{@thread.id}']" do
      assert_select "strong", text: "two@example.com"
      assert_select "span", text: /Is €49 right, @reader@example.com\?/
      assert_select "[data-note-replies]", text: "1 reply"
      assert_select "[data-note-new]", text: "new"
    end
    assert_select "span[data-admin--notes-target=counts]" do |nodes|
      assert_equal({ "total" => 1, "subjects" => { "ContentBlock-#{@block.id}" => 1 }, "unread" => [ "ContentBlock-#{@block.id}" ] }, JSON.parse(nodes.first["data-counts"]))
    end
    assert_select "#sidebar", count: 0 # a frame request gets the frame, not the shell
    assert_equal 2, Notes::Delivery.unread.where(user: users(:reader)).count # looking at the list reads nothing
  end

  test "the thread replaces the list in the same frame: Back, what it is on, the quote, the messages with a mention and a link" do
    sign_in_as(users(:reader))

    get "#{@base}/threads/#{@thread.id}", headers: frame

    assert_response :ok
    assert_select "turbo-frame#notes #notes-list", count: 0
    assert_select "turbo-frame#notes #note-thread-#{@thread.id}[data-notes-view=thread][data-state=open]" do
      assert_select "a[data-note-back][href='#{@base}']"
      assert_select "h3", text: "Rich text"
      assert_select "blockquote", text: "€49 a month"
      assert_select "#note-thread-#{@thread.id}-messages #note-message-#{@thread.first_message.id} [data-note-mention]", text: "@reader@example.com"
      assert_select "a[href='https://example.com']"
    end
    assert_select "span[data-admin--notes-target=counts]"
  end

  test "a long thread folds its middle, and a thread started on another language tab says so" do
    as(users(:two)) { 4.times { |index| Notes::Reply.call(@thread, body: "Reply #{index}") } }
    @thread.update!(origin_locale: "de")
    sign_in_as(users(:reader))

    get "#{@base}/threads/#{@thread.id}", headers: frame

    assert_select "#note-thread-#{@thread.id}-messages details summary", text: "Show 2 more"
    assert_select "#note-thread-#{@thread.id}-messages details [data-note-message]", count: 2
    assert_select "#note-thread-#{@thread.id}-messages [data-note-message]", count: 5
    assert_select "[data-note-badge=origin]", text: /Written on/

    get "#{@base}/threads/#{@thread.id}", params: { locale: "de" }, headers: frame
    assert_select "[data-note-badge=origin]", count: Locales.enabled?("de") ? 0 : 1
  end

  test "opening a thread marks the viewer's deliveries of that thread read, and no other" do
    other = as(users(:two)) { Notes::Start.call(@page, body: "And this, @[#{users(:reader).id}]") }.record
    sign_in_as(users(:reader))

    get "#{@base}/threads/#{@thread.id}", headers: frame

    assert_equal [ other.id ], Notes::Delivery.unread.where(user: users(:reader)).pluck(:thread_id)
    get @base, headers: frame
    assert_select "a#note-row-#{@thread.id}[data-unread]", count: 0
    assert_select "a#note-row-#{other.id}[data-unread]"
  end

  # `Notes::MarkRead` takes the container's row lock (FOR UPDATE on the page)
  # before it writes. A thread is opened far more often than it holds
  # something unread, so the GET asks first and runs the service only then.
  test "opening a thread with nothing unread for the viewer takes no row lock and writes nothing" do
    sign_in_as(users(:two)) # the author: nothing was delivered to them
    get "#{@base}/threads/#{@thread.id}", headers: frame

    quiet = capture_sql { get "#{@base}/threads/#{@thread.id}", headers: frame }
    assert_response :ok
    assert_empty quiet.grep(/FOR UPDATE|\AUPDATE "note_deliveries"/)

    sign_in_as(users(:reader)) # mentioned: one unread delivery
    get @base, headers: frame
    unread = capture_sql { get "#{@base}/threads/#{@thread.id}", headers: frame }
    assert_equal 1, unread.grep(/FROM "pages".*FOR UPDATE/).size
    assert_equal 1, unread.grep(/\AUPDATE "note_deliveries"/).size
    assert_operator unread.index { |sql| sql.include?("FOR UPDATE") }, :<, unread.index { |sql| sql.start_with?('UPDATE "note_deliveries"') }
  end

  # Review Focus 3, for a GET: the record goes to the trash between the
  # request's lookup and the mark. The service answers "This note is gone",
  # with nothing marked, and the request does not read that answer: what it
  # shows is decided by its own scoped lookups, so it is never an error.
  test "a thread whose page is trashed while it is being opened is still an ordinary answer, and nothing is marked read" do
    sign_in_as(users(:reader))
    mark_read = Notes::MarkRead.method(:call)
    result = nil
    page = @page # the override runs as a method of the service: no test ivars there
    trash_then_mark = lambda do |**arguments|
      page.update_columns(trashed_at: Time.current) # version: none (the race itself, set up by the test)
      result = mark_read.call(**arguments)
    end

    with_singleton_override(Notes::MarkRead, :call, trash_then_mark) { get "#{@base}/threads/#{@thread.id}", headers: frame }

    assert_equal [ I18n.t("admin.notes.errors.gone.note") ], result.errors
    assert_response :ok
    assert_equal 1, Notes::Delivery.unread.where(user: users(:reader)).count
  end

  test "a thread purged while it is being opened is not found" do
    sign_in_as(users(:reader))
    mark_read = Notes::MarkRead.method(:call)
    thread_id = @thread.id
    purge_then_mark = lambda do |**arguments|
      Notes::Thread.find(thread_id).destroy!
      mark_read.call(**arguments)
    end

    with_singleton_override(Notes::MarkRead, :call, purge_then_mark) { get "#{@base}/threads/#{@thread.id}", headers: frame }

    assert_response :not_found
  end

  test "pinned rows come first and say what they are on; the resolved rows and the counts are fetched on their own" do
    as(users(:two)) do
      Notes::Pin.call(@thread)
      Notes::Resolve.call(Notes::Start.call(@page, body: "Done and dusted").record)
    end
    sign_in_as(users(:reader))

    get @base, headers: frame
    assert_select "section#notes-pinned a#note-row-#{@thread.id}", text: /Rich text/
    assert_select "details#notes-resolved-section turbo-frame#notes-resolved[loading=lazy][src='#{@base}/resolved']"

    get "#{@base}/resolved"
    assert_select "turbo-frame#notes-resolved a[data-note-row][data-turbo-frame=notes]", text: /Done and dusted/

    get "#{@base}/counts"
    assert_equal({ "total" => 1, "subjects" => { "ContentBlock-#{@block.id}" => 1 }, "unread" => [ "ContentBlock-#{@block.id}" ] }, response.parsed_body)
  end

  test "a record without notes shows the empty state with New note" do
    quiet = create_page(title: "Quiet")
    sign_in_as(users(:reader))

    get "/cs-studio/notes/page/#{quiet.id}", headers: frame

    assert_select "#notes-list a[data-note-new-link][href='/cs-studio/notes/page/#{quiet.id}?compose=Page-#{quiet.id}']"
  end

  test "outside the read scope every part is not found, never forbidden" do
    other = create_page(title: "Other")
    elsewhere = as(users(:two)) { Notes::Start.call(other, body: "Elsewhere") }.record
    sign_in_as(@stranger)

    [ "", "/resolved", "/counts", "/threads/#{@thread.id}" ].each do |part|
      get "#{@base}#{part}"
      assert_response :not_found, part
    end

    sign_in_as(users(:reader))
    get "#{@base}/threads/#{elsewhere.id}" # a real thread, of another page
    assert_response :not_found
    get "/cs-studio/notes/page/999999999"
    assert_response :not_found
  end

  test "a trashed page's notes are not found; an image's need the media right" do
    asset = create_media_asset
    as(users(:two)) { Notes::Start.call(asset, body: "Crop it") }
    @page.update!(trashed_at: Time.current)

    sign_in_as(users(:two))
    get @base
    assert_response :not_found
    get "/cs-studio/notes/media/#{asset.id}", headers: frame
    assert_response :ok
    assert_select "a[data-note-row]", count: 1

    sign_in_as(@stranger)
    get "/cs-studio/notes/media/#{asset.id}"
    assert_response :forbidden
  end

  test "the list costs the same statements with one thread as with nine" do
    sign_in_as(users(:two))
    get @base, headers: frame
    one = capture_sql { get @base, headers: frame }.size
    as(users(:reader)) { 8.times { |index| Notes::Reply.call(Notes::Start.call([ @page, @block ][index % 2], body: "Note #{index}").record, body: "And @[#{users(:two).id}]") } }
    get @base, headers: frame

    assert_equal one, capture_sql { get @base, headers: frame }.size
  end
end
