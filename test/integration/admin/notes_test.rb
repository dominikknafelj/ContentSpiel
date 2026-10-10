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
    # `#notes-open` is the editor header's button (the stable ids table): the
    # section of open threads has an id of its own.
    assert_select "#notes-open", count: 0
    assert_select "section#notes-open-list[aria-labelledby=notes-open-list-title] h3#notes-open-list-title"
    # Following a row marks it read, so a hover must not fetch it (Turbo's prefetch).
    assert_select "a#note-row-#{@thread.id}[data-turbo-prefetch=false]"
    assert_select "section#notes-open-list section#notes-group-ContentBlock-#{@block.id} a#note-row-#{@thread.id}[data-note-row][data-unread][href='#{@base}/threads/#{@thread.id}']" do
      assert_select "strong", text: "two"
      assert_select "span", text: /Is €49 right, @reader\?/
      assert_select "[data-note-replies]", text: "1 reply"
      assert_select "[data-note-new]", text: "new"
    end
    assert_select "span[data-admin--notes--drawer-target=counts]" do |nodes|
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
      # The type as the label, then what tells the block from others of its
      # type: an empty one's place on the page (the handoff's decision 8).
      assert_select "h3 [data-note-subject-type]", text: "Rich text"
      assert_select "h3 [data-note-subject-words][class~='text-xs'][class~='text-dim'][class~='truncate']", text: "Block 1"
      assert_select "blockquote", text: "€49 a month"
      assert_select "figure[data-note-quote] > figcaption", text: "Quoted"
      assert_select "figure div figcaption", count: 0
      assert_select "#note-thread-#{@thread.id}-messages #note-message-#{@thread.first_message.id} [data-note-mention]", text: "@reader"
      assert_select "a[href='https://example.com']"
    end
    assert_select "span[data-admin--notes--drawer-target=counts]"
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

  test "a thread purged while it is being opened is gone: the list says so" do
    sign_in_as(users(:reader))
    mark_read = Notes::MarkRead.method(:call)
    thread_id = @thread.id
    purge_then_mark = lambda do |**arguments|
      Notes::Thread.find(thread_id).destroy!
      mark_read.call(**arguments)
    end

    with_singleton_override(Notes::MarkRead, :call, purge_then_mark) { get "#{@base}/threads/#{@thread.id}", headers: frame }

    assert_redirected_to "#{@base}?notice=gone"
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

    assert_select "details#notes-resolved-section summary", text: "Resolved (1)"

    get "#{@base}/resolved"
    assert_select "turbo-frame#notes-resolved a[data-note-row][data-turbo-frame=notes][data-turbo-prefetch=false]", text: /Done and dusted/

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
    # A real thread, of another page: among this page's it is gone, and the
    # list says so (nothing of it is shown, and nothing is marked read).
    get "#{@base}/threads/#{elsewhere.id}"
    assert_redirected_to "#{@base}?notice=gone"
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

  # Later tasks add work per message (edit forms, reactions, files): these are
  # the tests that catch an N+1 there.
  test "a thread costs the same statements with two messages as with twelve, with nothing unread and with something unread" do
    thread_url = "#{@base}/threads/#{@thread.id}"
    reply = ->(count) { as(users(:two)) { count.times { |index| Notes::Reply.call(@thread, body: "Reply #{index} for @[#{users(:reader).id}] and @[#{users(:one).id}]") } } }
    reply.call(1)

    sign_in_as(users(:two)) # the author of every message: nothing is delivered to them
    get thread_url, headers: frame
    quiet = capture_sql { get thread_url, headers: frame }.size
    sign_in_as(users(:reader)) # mentioned in every message
    unread = capture_sql { get thread_url, headers: frame }.size
    assert_operator unread, :>, quiet

    reply.call(10)
    assert_equal 12, @thread.messages.count

    sign_in_as(users(:two))
    get thread_url, headers: frame
    assert_equal quiet, capture_sql { get thread_url, headers: frame }.size
    assert_select "[data-note-message]", count: 12
    sign_in_as(users(:reader))
    assert_equal unread, capture_sql { get thread_url, headers: frame }.size
    assert_empty Notes::Delivery.unread.where(user: users(:reader), thread: @thread)
  end

  test "the resolved rows cost the same statements for one thread as for eight" do
    resolve = lambda do |count|
      as(users(:reader)) do
        count.times { |index| Notes::Resolve.call(Notes::Reply.call(Notes::Start.call([ @page, @block ][index % 2], body: "Done #{index}").record, body: "Yes @[#{users(:two).id}]").record.thread) }
      end
    end
    resolve.call(1)
    sign_in_as(users(:two))
    get "#{@base}/resolved"
    one = capture_sql { get "#{@base}/resolved" }.size
    assert_select "a[data-note-row]", count: 1

    resolve.call(7)

    assert_equal one, capture_sql { get "#{@base}/resolved" }.size
    assert_select "a[data-note-row]", count: 8
  end

  # The handoff's decision 8.
  test "a group is headed by the block's type and its first words in the tab's language, an image's file name, or its place on the page" do
    with_locales(%w[en de], default: "en") do
      @block.assign_body(rich_doc("Our prices start at forty nine euros a month."), locale: :en)
      @block.assign_body(rich_doc("Unsere Preise beginnen hier"), locale: :de)
      @block.save!
      section = @page.content_blocks.create!(block_type: "section", position: 1, settings: { "layout" => "two" })
      image = @page.content_blocks.create!(block_type: "image", section: section, section_column: 2, position: 0, media_asset: create_media_asset)
      empty = @page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0)
      as(users(:two)) { [ image, empty, @page ].each { |subject| Notes::Start.call(subject, body: "A note") } }
      sign_in_as(users(:two))

      get @base, headers: frame

      heading = ->(record) { "section#notes-group-#{Notes.key(record)} h4" }
      assert_select "#{heading.call(@block)} [data-note-subject-type][class~='font-cs-mono'][class~='uppercase']", text: "Rich text"
      assert_select "#{heading.call(@block)} [data-note-subject-words][class~='text-xs'][class~='text-dim'][class~='truncate']", text: "Our prices start at forty nine…"
      assert_select "#{heading.call(image)} [data-note-subject-type]", text: "Section › Column 2 · Image"
      assert_select "#{heading.call(image)} [data-note-subject-words]", text: "tiny.png"
      assert_select "#{heading.call(empty)} [data-note-subject-type]", text: "Section › Column 1 · Rich text"
      assert_select "#{heading.call(empty)} [data-note-subject-words]", text: "Block 3"
      # The record itself has its words and nothing after them.
      assert_select "#{heading.call(@page)} [data-note-subject-type]", text: "Whole page"
      assert_select "#{heading.call(@page)} [data-note-subject-words]", count: 0

      get @base, params: { locale: "de" }, headers: frame
      assert_select "#{heading.call(@block)} [data-note-subject-words]", text: "Unsere Preise beginnen hier"
    end
  end

  test "the list costs the same statements whatever the number of blocks with notes, image blocks among them" do
    images = 4.times.map { |index| @page.content_blocks.create!(block_type: "image", position: 1 + index, media_asset: create_media_asset) }
    texts = 4.times.map { |index| @page.content_blocks.create!(block_type: "rich_text", position: 5 + index) }
    as(users(:reader)) { [ images.first, texts.first ].each { |block| Notes::Start.call(block, body: "One") } }
    sign_in_as(users(:two))
    get @base, headers: frame
    few = capture_sql { get @base, headers: frame }.size

    as(users(:reader)) { (images.drop(1) + texts.drop(1)).each { |block| 2.times { Notes::Start.call(block, body: "More") } } }
    get @base, headers: frame

    assert_equal few, capture_sql { get @base, headers: frame }.size
    assert_select "h4 [data-note-subject-words]", text: "tiny.png", count: 4
  end

  test "the record's own group is headed Whole page, Whole post or This image" do
    post = create_post(title: "News")
    asset = create_media_asset
    as(users(:two)) { [ @page, post, asset ].each { |record| Notes::Start.call(record, body: "On the record itself") } }
    sign_in_as(users(:two))

    { "page/#{@page.id}" => [ "Page-#{@page.id}", "Whole page" ], "post/#{post.id}" => [ "Post-#{post.id}", "Whole post" ],
      "media/#{asset.id}" => [ "MediaAsset-#{asset.id}", "This image" ] }.each do |path, (key, heading)|
      get "/cs-studio/notes/#{path}", headers: frame
      assert_select "section#notes-group-#{key} h4", text: heading
    end
  end
end
