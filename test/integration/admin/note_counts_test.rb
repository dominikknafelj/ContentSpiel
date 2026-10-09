require "test_helper"

# The open-note count wherever a record is listed (notes spec §4.4): one
# grouped query per surface, and one beside it for "unread for you", whatever
# the number of rows and of threads. Each count is the notes pill
# (`.admin-notes-marker`, the block card's own), drawn by the server with its
# number: these lists are not live, their counts are fresh on load.
class Admin::NoteCountsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @post = create_post(title: "Hello")
    @quiet = create_post(title: "Quiet")
    @asset = create_media_asset
    as(users(:two)) do
      [ @page, @block, @post, @asset ].each { |subject| Notes::Start.call(subject, body: "A note") }
      Notes::Resolve.call(Notes::Start.call(@post, body: "Done").record)
    end
    sign_in_as(users(:two))
  end

  def more_notes = as(users(:reader)) { 6.times { [ @block, @post ].each { |subject| Notes::Start.call(subject, body: "More") } } }

  def more_image_notes = as(users(:two)) { 6.times { Notes::Start.call(@asset, body: "More") } }

  # The statements that read notes: what a surface pays for its counts.
  def note_statements(path) = capture_sql { get path }.grep(/"note_/)

  test "the posts list has a Notes column: the open count as a link that opens the post with its drawer, nothing for a post without" do
    get "/cs-studio/posts"

    # The handoff's header: only the 12px icon, named for a screen reader and by its title.
    assert_select "table.admin-posts-table th[title='Open notes'][class~='w-14']", text: "Notes" do
      assert_select "svg[class~='size-3']"
    end
    assert_select "tr#post_#{@post.id} a[data-notes-count][href='/cs-studio/posts/#{@post.id}?notes=open'][aria-label='1 open note']", text: "1"
    # The pill without an icon, neutral.
    assert_select "tr#post_#{@post.id} a.admin-notes-marker[data-notes-count][data-has-notes]:not([data-unread])" do
      assert_select "svg", count: 0
    end
    assert_select "tr#post_#{@quiet.id} [data-notes-count]", count: 0
  end

  test "the page tree shows a page's open notes and its blocks' together" do
    get "/cs-studio/pages/#{@page.id}"

    assert_select "#tree-column li[data-page-id='#{@page.id}'] > div span[data-notes-marker][aria-label='2 open notes']", text: "2"
    # The 18px pill with a 12px icon, after the translation markers.
    assert_select "#tree-column li[data-page-id='#{@page.id}'] > div span.admin-notes-marker.admin-notes-marker--small[data-has-notes] svg[class~='size-3']"
    assert_select "#tree-column li[data-page-id='#{root_page.id}'] > div [data-notes-marker]", count: 0
  end

  test "a media tile has a count chip on its image, the picker's tile has none, and the panel embeds the image's notes" do
    get "/cs-studio/media", params: { selected: @asset.id, thread: 7 }

    assert_select "#media-asset-#{@asset.id} span[data-notes-chip][aria-label='1 open note']", text: "1"
    assert_select "#media-asset-#{@asset.id} span.admin-notes-marker.admin-notes-marker--on-image[data-has-notes] svg[class~='size-3']"
    assert_select "#media-panel #media-notes turbo-frame#notes[loading=lazy][src='/cs-studio/notes/media/#{@asset.id}/threads/7?view=media']"
    get "/cs-studio/media", params: { selected: @asset.id }
    assert_select "#media-notes turbo-frame#notes[src='/cs-studio/notes/media/#{@asset.id}?view=media']"
    # The handoff's header, "NOTES · 1 OPEN": the number follows the counts
    # every answer of the frame brings, and the page has its own copy.
    assert_select "#media-notes h3", text: /\ANotes\s+·\s+1 open\z/
    assert_select "#media-notes h3 [data-admin--notes-target=total]", text: "1"
    assert_select "#media-notes #notes-counts[data-admin--notes-target=counts]"
    # No drawer on this screen (the spec wins over the handoff's "Open in drawer").
    assert_select "aside#notes-drawer", count: 0
    # Asked of the frame's own answer: in the page above the frame is not loaded yet.
    get "/cs-studio/notes/media/#{@asset.id}", params: { view: "media" }, headers: { "Turbo-Frame" => "notes" }
    assert_response :success
    assert_select "a[data-note-row]", count: 1
    assert_select "a[href*='notes=open']", count: 0
    assert_select "a, button", text: /open in drawer/i, count: 0
    get "/cs-studio/media", params: { selected: @asset.id }

    # The panel is the image's autosaving form, and a form cannot nest: the
    # frame brings forms of its own, and inside an autosave form a note's
    # field would be the image's.
    assert_select "#media-panel form[data-controller~='admin--autosave']"
    assert_select "#media-panel form #media-notes", count: 0
    assert_select "form turbo-frame#notes", count: 0
    assert_select "[data-controller~='admin--autosave'] turbo-frame#notes", count: 0

    get "/cs-studio/media", params: { picker: 1 }
    assert_select "[data-notes-chip]", count: 0
  end

  test "a thread that is not a number does not travel to the panel's frame" do
    get "/cs-studio/media", params: { selected: @asset.id, thread: "7/../../x" }

    assert_select "#media-notes turbo-frame#notes[src='/cs-studio/notes/media/#{@asset.id}?view=media']"
  end

  test "an image without open notes has the header without a number" do
    quiet = create_media_asset

    get "/cs-studio/media", params: { selected: quiet.id }

    assert_select "#media-notes h3 [data-admin--notes-target=total][hidden]"
    assert_select "#media-asset-#{quiet.id} [data-notes-chip]", count: 0
  end

  test "the panel's notes are there for someone who may only look at the image" do
    sign_in_as(users(:author))

    get "/cs-studio/media", params: { selected: @asset.id }

    assert_response :success
    assert_select "#media-panel form[data-controller~='admin--autosave']", count: 0
    assert_select "#media-panel #media-notes turbo-frame#notes"
  end

  test "a note started in the media panel records where it was written" do
    post "/cs-studio/notes/media/#{@asset.id}/threads", params: { body: "Crop tighter", view: "media" }

    assert_redirected_to %r{/cs-studio/notes/media/#{@asset.id}/threads/\d+\?view=media\z}
    assert_equal "media", Notes::Thread.order(:id).last.origin_view
  end

  test "in the media panel a thread's first line is not cut short, in the drawer it is" do
    get "/cs-studio/notes/media/#{@asset.id}", params: { view: "media" }
    assert_select "a[data-note-row] span.break-words", text: "A note"
    assert_select "a[data-note-row] span.truncate", count: 0

    get "/cs-studio/notes/post/#{@post.id}"
    assert_select "a[data-note-row] span.truncate", text: "A note"
  end

  test "the tile an autosave in the panel draws again keeps its chip" do
    as(users(:one)) { Notes::Start.call(@asset, body: "For @[#{users(:two).id}]") }

    patch "/cs-studio/media/#{@asset.id}", params: { media_asset: { title: "Renamed" } }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[target='media-asset-#{@asset.id}'] template span[data-notes-chip][data-unread]", text: "2"
  end

  # `PATCH /media/:id` is open to `media.manage` alone (`Media::Save`), the
  # notes of an image to `media.upload` alone (`Admin::NoteContainer`): the
  # tile such a save draws again says nothing about notes its reader may not open.
  test "the tile an autosave draws for someone who may manage images but not open their notes has no count" do
    group = access_control_groups(:branch_editors)
    upload = AccessControl::Grant.create!(group: group, permission: "media.upload", scope: {})
    # Mentioned while they could still open the library: unread, so a leak would be in accent.
    as(users(:one)) { assert Notes::Start.call(@asset, body: "For @[#{users(:editor_branch).id}]").ok? }
    assert_equal 1, Notes::Delivery.unread.where(user: users(:editor_branch)).count
    upload.destroy!
    AccessControl::Grant.create!(group: group, permission: "media.manage", scope: {})
    sign_in_as(users(:editor_branch))

    patch "/cs-studio/media/#{@asset.id}", params: { media_asset: { title: "Renamed" } }, as: :turbo_stream

    assert_response :success
    assert_equal "Renamed", @asset.reload.title
    assert_select "turbo-stream[target='media-asset-#{@asset.id}'] template li"
    assert_select "[data-notes-chip]", count: 0
    assert_select "[data-unread]", count: 0
    assert_not_includes response.body, "open note"
    get "/cs-studio/notes/media/#{@asset.id}"
    assert_response :forbidden
  end

  # A context-only ancestor is drawn so the readable page has its path to the
  # root; it shows nothing but its title. A count there would say something
  # about a page the viewer may not open, in accent if they were once
  # mentioned on it. The row's template draws no marker for such a row
  # whatever it is handed, so the test also looks at what the tree ASKS
  # `Notes::Counts` for: the ancestor's id is never among the ids, in either read.
  test "the tree shows no count on a context-only ancestor, though the viewer has an unread mention there, and the readable child's own" do
    child = create_page(title: "Plans", parent: @page)
    group = access_control_groups(:branch_editors)
    viewer = users(:editor_branch)
    wide = AccessControl::Grant.create!(group: group, permission: "pages.read", scope: { "page_ids" => [ @page.id ] })
    as(users(:one)) do
      assert Notes::Start.call(@page, body: "For @[#{viewer.id}]").ok?
      assert Notes::Start.call(child, body: "For @[#{viewer.id}] too").ok?
    end
    wide.destroy!
    AccessControl::Grant.create!(group: group, permission: "pages.read", scope: { "page_ids" => [ child.id ] })
    assert_equal 2, Notes::Delivery.unread.where(user: viewer).count
    assert_operator Notes::Counts.by_container("Page", [ @page.id ]).fetch(@page.id), :>=, 1
    assert_includes Notes::Counts.unread_among("Page", [ @page.id ], viewer), @page.id
    sign_in_as(viewer)
    asked = []
    counts = Notes::Counts.method(:by_container)
    unread = Notes::Counts.method(:unread_among)
    recording_counts = ->(type, ids) { asked << [ :by_container, type, ids ] and counts.call(type, ids) }
    recording_unread = ->(type, ids, user) { asked << [ :unread_among, type, ids ] and unread.call(type, ids, user) }

    with_singleton_override(Notes::Counts, :by_container, recording_counts) do
      with_singleton_override(Notes::Counts, :unread_among, recording_unread) { get "/cs-studio/pages/#{child.id}" }
    end

    assert_response :success
    assert_equal [ [ :by_container, "Page", [ child.id ] ], [ :unread_among, "Page", [ child.id ] ] ], asked
    assert_select "#tree-column li[data-page-id='#{@page.id}'][data-context-only]"
    assert_select "#tree-column li[data-page-id='#{@page.id}'] > div [data-notes-marker]", count: 0
    assert_select "#tree-column li[data-page-id='#{@page.id}'] > div [data-unread]", count: 0
    assert_select "#tree-column li[data-page-id='#{child.id}'] > div span[data-notes-marker][data-unread]", text: "1"
    assert_select "#tree-column [data-notes-marker]", count: 1
  end

  # A link to a thread outlives the thread (it was deleted, its block was).
  # The frame's GET then answers the list with a sentence, as a write does:
  # a 404 inside a lazy frame is "Content missing" and an error in the console.
  { "page" => -> { @page }, "post" => -> { @post }, "media" => -> { @asset } }.each do |type, record|
    test "a thread that is gone answers the #{type}'s list with a sentence, not a 404" do
      container = instance_exec(&record)
      base = "/cs-studio/notes/#{type}/#{container.id}"
      gone = Notes::Thread.find_by!(subject: container)
      thread_path = "#{base}/threads/#{gone.id}"
      gone.destroy!
      query = type == "media" ? "?view=media" : ""

      get "#{thread_path}#{query}", headers: { "Turbo-Frame" => "notes" }

      assert_redirected_to "#{base}?notice=gone#{query.sub("?", "&")}"
      follow_redirect!(headers: { "Turbo-Frame" => "notes" })
      assert_response :success
      assert_select "turbo-frame#notes #notes-list [role=status]", text: /This note is gone/

      # A thread of another record is as gone as one that never was.
      get "#{base}/threads/#{Notes::Thread.where.not(container: container).first!.id}#{query}", headers: { "Turbo-Frame" => "notes" }
      assert_redirected_to "#{base}?notice=gone#{query.sub("?", "&")}"
    end
  end

  test "only the thread's absence is forgiven: a record out of scope is still not found, an image without the media right still forbidden" do
    @post.update!(trashed_at: Time.current)
    get "/cs-studio/notes/post/#{@post.id}/threads/999999999", headers: { "Turbo-Frame" => "notes" }
    assert_response :not_found
    get "/cs-studio/notes/page/999999999/threads/1", headers: { "Turbo-Frame" => "notes" }
    assert_response :not_found

    sign_in_as(users(:reader))
    get "/cs-studio/notes/media/#{@asset.id}/threads/999999999", headers: { "Turbo-Frame" => "notes" }
    assert_response :forbidden
  end

  test "each list costs the same statements whatever the number of threads" do
    paths = [ "/cs-studio/posts", "/cs-studio/pages/#{@page.id}", "/cs-studio/media" ]
    paths.each { |path| get path }
    few = paths.map { |path| capture_sql { get path }.size }
    more_notes
    more_image_notes
    paths.each { |path| get path }

    assert_equal few, paths.map { |path| capture_sql { get path }.size }
  end

  test "each list reads its counts in one statement and what is unread for the viewer in one beside it, whatever the number of rows" do
    paths = [ "/cs-studio/posts", "/cs-studio/pages/#{@page.id}", "/cs-studio/media" ]
    paths.each { |path| get path }
    # The page editor also reads its own record's counts for the drawer (two
    # statements, `Notes::Counts.for_container`); the tree beside it adds two.
    assert_equal [ 2, 4, 2 ], paths.map { |path| note_statements(path).size }

    as(users(:two)) do
      5.times do |n|
        Notes::Start.call(create_post(title: "Post #{n}"), body: "A note")
        Notes::Start.call(create_page(title: "Page #{n}"), body: "A note")
        Notes::Start.call(create_media_asset, body: "A note")
      end
    end
    paths.each { |path| get path }

    assert_equal [ 2, 4, 2 ], paths.map { |path| note_statements(path).size }
  end

  test "a count is accent for the person its thread is addressed to, and neutral for everyone else" do
    as(users(:one)) { [ @post, @page, @asset ].each { |subject| Notes::Start.call(subject, body: "For @[#{users(:two).id}]") } }

    get "/cs-studio/posts"
    assert_select "tr#post_#{@post.id} a[data-notes-count][data-unread]"
    get "/cs-studio/pages/#{@page.id}"
    assert_select "#tree-column li[data-page-id='#{@page.id}'] > div [data-notes-marker][data-unread]"
    get "/cs-studio/media"
    assert_select "#media-asset-#{@asset.id} [data-notes-chip][data-unread]"

    sign_in_as(users(:one))
    get "/cs-studio/posts"
    assert_select "[data-notes-count]"
    assert_select "[data-notes-count][data-unread]", count: 0
    get "/cs-studio/pages/#{@page.id}"
    assert_select "#tree-column [data-notes-marker][data-unread]", count: 0
    get "/cs-studio/media"
    assert_select "[data-notes-chip][data-unread]", count: 0
  end
end
