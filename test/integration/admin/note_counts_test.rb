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
    assert_select "#media-notes a", count: 0

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
