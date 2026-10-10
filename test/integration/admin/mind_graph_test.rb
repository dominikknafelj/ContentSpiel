require "test_helper"

# The mind graph's page (mind graph canvas spec §3.2): a frame -- heading,
# legend, filter, an empty canvas -- with NO graph data in it. The
# `admin--mind-graph` controller fetches the data from the URL the page names
# (`test/integration/admin/mind_graph_data_test.rb` covers that endpoint) and
# draws it (`test/system/admin/mind_graph_test.rb`). Same session gate as every
# other CS Studio screen -- not public.
class Admin::MindGraphTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  # Replaces MindGraphTest's (test/integration/mind_graph_test.rb) own
  # "an unauthenticated request cannot reach the mind graph".
  test "an unauthenticated request is redirected to sign-in" do
    get "/cs-studio/mind_graph"
    assert_redirected_to "/cs-studio/sign-in"
  end

  test "the page is a frame: no graph data in it, and the script is told where to get it" do
    sign_in_as(users(:one))
    a = create_post(title: "A very particular title")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))

    get "/cs-studio/mind_graph"

    assert_response :success
    assert_select "script#mind-graph-data", count: 0
    assert_no_match "A very particular title", response.body
    assert_select "[data-controller='admin--mind-graph'][data-url='/cs-studio/mind_graph/data'][data-state='loading']"
    assert_select "[data-controller='admin--mind-graph'][data-worker-url*='mind_graph/layout_worker'][data-d3-url*='d3-force']"
    assert_select "canvas[role='img'][tabindex='0'][aria-label]"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/mind_graph']", text: "Mind graph"
  end

  # The selection card's links (spec §5.3) are filled into templates the route
  # helpers built: the placeholders arrive literally, for the script to
  # replace with a URL-encoded id or name, and no path is written in JavaScript.
  test "the card's URL templates and the type labels ride on the element" do
    sign_in_as(users(:one))
    create_post(title: "A", content_type: "resume_entry")

    get "/cs-studio/mind_graph"

    assert_select "[data-controller='admin--mind-graph'][data-post-focus-url='/cs-studio/mind_graph?post=__ID__'][data-tag-focus-url='/cs-studio/mind_graph?tag=__ID__'][data-tag-posts-url='/cs-studio/posts?tag=__NAME__']"
    # A post's notes for its card (notes spec §4.4): the route takes digits
    # only, so the template is built for id 0 and the segment swapped.
    assert_select "[data-controller='admin--mind-graph'][data-post-notes-url='/cs-studio/notes/post/__ID__/threads']"
    labels = JSON.parse(css_select("[data-controller='admin--mind-graph']").first["data-type-labels"])
    assert_equal({ "resume_entry" => ContentTypes.fetch("resume_entry").label }, labels)
    assert_select "[data-mind-graph-card][hidden]:empty"
    assert_select "[data-mind-graph-tooltip][hidden]:empty"
  end

  # A type that is no longer registered has no label to send: the card shows
  # the stored name.
  test "a retired type has no entry among the type labels" do
    sign_in_as(users(:one))
    create_post(title: "A").update_columns(content_type: "gone_type")

    get "/cs-studio/mind_graph"

    assert_equal "{}", css_select("[data-controller='admin--mind-graph']").first["data-type-labels"]
  end

  # The strings the script shows are the server's (docs/reference/i18n.md): a
  # plural rides whole, for the script to choose a form by count.
  test "the script's messages ride on the element" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    messages = JSON.parse(css_select("[data-controller='admin--mind-graph']").first["data-messages"])
    assert_equal "The graph could not be loaded.", messages["mind_graph.script.load_failed"]
    assert_equal({ "one" => "%{figure} other post has no connections yet and isn't shown.", "other" => "%{figure} other posts have no connections yet and aren't shown." }, messages["mind_graph.script.isolated"])
    assert_equal({ "one" => "%{figure} post has no connections yet.", "other" => "%{figure} posts have no connections yet." }, messages["mind_graph.script.isolated_only"])
    assert_equal({ "one" => "%{count} tag", "other" => "%{count} tags" }, messages["mind_graph.script.card.tags"])
    assert_equal({ "one" => "Release %{count} pinned", "other" => "Release %{count} pinned" }, messages["mind_graph.script.release_pinned"])
    assert_equal "%{title}: post, %{count} connections. Shows it in the graph.", messages["mind_graph.script.list.select_post"]["other"]
    assert_equal "Posts · %{count}", messages["mind_graph.script.list.posts"]
    assert_equal "Showing the %{shown} nearest of %{total} posts around this one.", messages["mind_graph.script.capped_local"]
    assert_equal "Open notes · %{count}", messages["mind_graph.script.card.notes.title"]
    assert_equal %w[capped capped_local card.close card.focus card.notes.add card.notes.deleted_user card.notes.failed card.notes.label card.notes.more card.notes.replies card.notes.sending
                    card.notes.title card.notes.unread card.open_post card.pin card.related card.show_tagged card.status.draft card.status.live card.status.scheduled
                    card.tag card.tag_posts card.tags card.unpin isolated isolated_only list.empty list.posts list.select_post list.select_tag list.tags load_failed loading no_connections
                    release_pinned retry search.count search.failed search.none search.post search.tag summary worker_failed].map { |key| "mind_graph.script.#{key}" },
                 messages.keys.grep(/\Amind_graph/).sort
  end

  # The frame of the round of 2026-10-08: the search, the graph and the list
  # in that order in the document (the Tab key's order), the list as an empty
  # region the script fills, "Release N pinned" hidden until something is
  # pinned, and no collapsed list of links under the canvas.
  test "the frame holds the search first, then the canvas with its controls, then the list; nothing is pinned" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "[data-controller='admin--mind-graph'] > *", count: 3
    assert_select "[data-controller='admin--mind-graph'] > :nth-child(1) #mind-graph-search"
    assert_select "[data-controller='admin--mind-graph'] > :nth-child(2) canvas"
    assert_select "[data-controller='admin--mind-graph'] > :nth-child(3)[data-mind-graph-list][role='region'][aria-label='Posts and tags in this graph']:empty"
    assert_select "details", count: 0
    assert_select "button[data-mind-graph-release][hidden][data-action='admin--mind-graph#releasePinned']:empty"
    assert_select "[role='group'][aria-label='Zoom'] button", count: 3
    assert_select "button[aria-label='Zoom out'][title='Zoom out']", text: "−"
    assert_select "button[aria-label='Zoom in'][title='Zoom in']", text: "+"
    assert_select "button[aria-label='Fit all'][title='Fit all']", text: "Fit"
    assert_select "[data-mind-graph-zoom]:empty"
    assert_select "[data-mind-graph-card][hidden][tabindex='-1']:empty"
  end

  # The card's actions are CS Studio's buttons and a type's dot is the shared
  # dot: the script is handed their classes, it does not hold copies.
  test "the button and dot classes the script uses are the shared components' own" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    element = css_select("[data-controller='admin--mind-graph']").first
    buttons = JSON.parse(element["data-button-classes"])
    assert_equal "#{Admin::ButtonComponent::SMALL_CLASS} #{Admin::ButtonComponent::VARIANT_CLASSES[:primary]}", buttons["primary"]
    assert_equal "#{Admin::ButtonComponent::SMALL_CLASS} #{Admin::ButtonComponent::VARIANT_CLASSES[:secondary]}", buttons["secondary"]
    assert_equal Admin::ContentTypeDotComponent::FILLED + Admin::ContentTypeDotComponent::RINGS, JSON.parse(element["data-dot-classes"])
  end

  test "the data url carries the focus, the depth and the editing language" do
    sign_in_as(users(:one))
    with_locales(%w[en de], default: "en")
    post = create_post(title: "A")

    get "/cs-studio/mind_graph", params: { post: post.id, depth: 2, locale: "de" }

    url = css_select("[data-controller='admin--mind-graph']").first["data-url"]
    assert_equal "/cs-studio/mind_graph/data", URI(url).path
    assert_equal({ "post" => post.id.to_s, "depth" => "2", "locale" => "de" }, Rack::Utils.parse_query(URI(url).query))
  end

  test "a tag focus rides in the data url, and a depth other than 1 or 2 is read as 1" do
    sign_in_as(users(:one))
    create_post(title: "A", tags: [ "t" ])
    tag = Tag.find_by!(name: "t")

    get "/cs-studio/mind_graph", params: { tag: tag.id, depth: 7 }

    url = css_select("[data-controller='admin--mind-graph']").first["data-url"]
    assert_equal({ "tag" => tag.id.to_s, "depth" => "1" }, Rack::Utils.parse_query(URI(url).query))
  end

  test "a focus outside the viewer's scope, in the trash or unknown is 404" do
    sign_in_as(users(:one))
    gone = create_post(title: "Gone")
    gone.update_column(:trashed_at, Time.current)

    [ { post: 0 }, { post: gone.id }, { tag: 0 } ].each do |params|
      get "/cs-studio/mind_graph", params: params
      assert_response :not_found, "expected 404 for #{params}"
    end
  end

  test "a post the viewer may not read is not found as a focus, and neither is a tag only it carries" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    own = create_post(title: "Own")
    own.update_column(:author_id, users(:author).id)
    other = create_post(title: "Other", tags: [ "theirs" ])
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph", params: { post: own.id }
    assert_response :success

    [ { post: other.id }, { tag: Tag.find_by!(name: "theirs").id } ].each do |params|
      get "/cs-studio/mind_graph", params: params
      assert_response :not_found, "expected 404 for #{params}"
    end
  end

  test "a viewer who can read no post sees 'No posts yet.' and no canvas, however many exist" do
    create_post(title: "Hidden from them")
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_select "[data-mind-graph-empty=no-posts]", text: "No posts yet."
    assert_select "canvas", count: 0
    assert_select "[data-controller='admin--mind-graph']", count: 0
    assert_not_includes response.body, "Hidden from them"
  end

  test "with no posts at all, 'No posts yet.' instead of an empty canvas" do
    sign_in_as(users(:one))

    get "/cs-studio/mind_graph"

    assert_response :success
    assert_select "[data-mind-graph-empty=no-posts]", text: "No posts yet."
    assert_select "[data-controller~='admin--mind-graph']", count: 0
  end

  test "the legend names only the content types of the viewer's posts, plus the shapes" do
    sign_in_as(users(:one))
    create_post(title: "A", content_type: "resume_entry")

    get "/cs-studio/mind_graph"

    assert_select ".admin-mind-graph-legend [data-legend-type]", count: 1
    assert_select "[data-legend-type='resume_entry']", text: /#{ContentTypes.fetch("resume_entry").label}/
    assert_select "[data-legend='tag']", text: /Tag/
    assert_select "[data-legend='hollow']", text: /Draft or scheduled/
    assert_select "[data-legend='related']", text: /Related post/
    assert_select "[data-legend='tag-edge']", text: /Shares a tag/
    assert_select "[data-legend='notes']", text: /Open notes/
    assert_select "[data-legend='retired']", count: 0
  end

  test "the legend names no content type of a post the viewer can't read" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    create_post(title: "Own").update_column(:author_id, users(:author).id)
    create_post(title: "Theirs", content_type: "resume_entry")
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_select "[data-legend-type]", count: 1
    assert_select "[data-legend-type='resume_entry']", count: 0
  end

  test "a post of a type that is no longer registered adds the Retired type entry" do
    sign_in_as(users(:one))
    create_post(title: "A").update_column(:content_type, "gone/thing")

    get "/cs-studio/mind_graph"

    assert_select "[data-legend='retired']", text: /Retired type/
    assert_select "[data-legend-type]", count: 0
  end

  test "the filter is All, Related and Tags, with All chosen" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "fieldset input[type=radio][name=mind_graph_filter]", count: 3
    assert_select "input#mind-graph-filter-all[checked]"
    assert_select "label[for=mind-graph-filter-related]", text: "Related"
    assert_select "label[for=mind-graph-filter-tag]", text: "Tags"
  end

  # Mind graph canvas spec §5.7: the tab order is the search, the filter, the
  # zoom buttons, then the canvas. The buttons sit in the canvas's corner on
  # screen, but they come BEFORE it in the document, which is what the Tab key
  # follows -- as the search does, though on screen it stands on the right.
  # ("Release N pinned" is first among the buttons, hidden until a node is
  # pinned; a button is named here by its `aria-label`, as a screen reader
  # names it.)
  test "the tab order is the search, the filter, the zoom buttons, then the canvas" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    order = css_select("[data-controller='admin--mind-graph'] input[type=search], [data-controller='admin--mind-graph'] input[type=radio], [data-controller='admin--mind-graph'] button, [data-controller='admin--mind-graph'] canvas")
      .map { |node| node.name == "button" ? (node["aria-label"] || (node["hidden"] ? "hidden" : node.text.strip)) : node.name }
    assert_equal [ "input", "input", "input", "input", "hidden", "Zoom out", "Zoom in", "Fit all", "canvas" ], order
    assert_equal "search", css_select("[data-controller='admin--mind-graph'] input, [data-controller='admin--mind-graph'] button, [data-controller='admin--mind-graph'] canvas").first["type"]
    # Nothing is taken out of the Tab order or moved within it; only the card
    # can be handed the focus by the script (`tabindex="-1"`).
    assert_equal [ "aside" ], css_select("[data-controller='admin--mind-graph'] [tabindex]:not([tabindex='0'])").map(&:name)
  end

  test "a focused view names its focus, offers both depths and the way back" do
    sign_in_as(users(:one))
    post = create_post(title: "Alpha")

    get "/cs-studio/mind_graph", params: { post: post.id }

    assert_select "[data-controller='admin--mind-graph'] [data-mind-graph-focus]", text: /Around “Alpha”/
    link = css_select("[data-mind-graph-focus] a").find { |a| a.text == "2" }
    assert_equal({ "post" => post.id.to_s, "depth" => "2" }, Rack::Utils.parse_query(URI(link["href"]).query))
    assert_select "[data-mind-graph-focus] [aria-current='true']", text: /\ADepth\s+1\z/
    assert_select "[data-mind-graph-focus] a[href='/cs-studio/mind_graph']", text: "Whole graph"

    get "/cs-studio/mind_graph", params: { post: post.id, depth: 2 }
    assert_select "[data-mind-graph-focus] [aria-current='true']", text: /\ADepth\s+2\z/
    one = css_select("[data-mind-graph-focus] a").find { |a| a.text == "1" }
    assert_equal({ "post" => post.id.to_s }, Rack::Utils.parse_query(URI(one["href"]).query))
  end

  test "a tag focus is named as a tag and its depth links keep the tag" do
    sign_in_as(users(:one))
    create_post(title: "A", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "ruby")

    get "/cs-studio/mind_graph", params: { tag: tag.id }

    assert_select "[data-mind-graph-focus]", text: /Around the tag “ruby”/
    link = css_select("[data-mind-graph-focus] a").find { |a| a.text == "2" }
    assert_equal({ "tag" => tag.id.to_s, "depth" => "2" }, Rack::Utils.parse_query(URI(link["href"]).query))
  end

  test "a focus title with markup in it is escaped" do
    sign_in_as(users(:one))
    post = create_post(title: "<b>x</b>")

    get "/cs-studio/mind_graph", params: { post: post.id }

    assert_select "[data-mind-graph-focus] b", count: 0
  end

  test "the global view has no focus bar, and every view has the search field inside the controller's element" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "[data-mind-graph-focus]", count: 0
    assert_select "[data-controller='admin--mind-graph'] [data-mind-graph-search][data-url^='/cs-studio/mind_graph/search'] input[type=search]#mind-graph-search"
    assert_select "label.sr-only[for=mind-graph-search]", text: "Find a post or tag"
    assert_select "[data-mind-graph-search] [data-mind-graph-results][hidden]:empty"
  end

  # Spec §5.7: the search comes first, then (in a local view) the focus bar's
  # links, then the filter, the zoom buttons and the canvas. The bar is the
  # first row of the graph's own column, above the legend.
  test "in a local view the tab order is the search, the bar's links, the filter, the zoom buttons, the canvas" do
    sign_in_as(users(:one))
    post = create_post(title: "A")

    get "/cs-studio/mind_graph", params: { post: post.id }

    order = css_select(%w[input[type=search] [data-mind-graph-focus]\ a input[type=radio] button canvas].map { |part| "[data-controller='admin--mind-graph'] #{part}" }.join(", "))
      .map { |node| { "button" => node["aria-label"] || "hidden", "canvas" => "canvas" }.fetch(node.name) { node.name == "a" ? "link:#{node.text.strip}" : node["type"] } }
    assert_equal [ "search", "link:2", "link:Whole graph", "radio", "radio", "radio", "hidden", "Zoom out", "Zoom in", "Fit all", "canvas" ], order
  end

  # Spec §5.7: the list comes after the canvas (and the card), so it is the
  # last stop -- it can hold two thousand rows; it starts empty, the script
  # fills it.
  test "the list comes last and empty" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "[data-controller='admin--mind-graph'] [data-mind-graph-list]:empty"
    order = css_select("[data-controller='admin--mind-graph'] canvas, [data-controller='admin--mind-graph'] [data-mind-graph-card], [data-controller='admin--mind-graph'] [data-mind-graph-list]").map(&:name)
    assert_equal %w[canvas aside div], order
  end

  # The current depth is text, not a link that can't be followed: no link
  # role, nothing disabled, and its name is its own text -- the word "Depth",
  # hidden from the eye (the row already says it once), then the number.
  test "the depth switch names its depth for assistive technology, the current one too" do
    sign_in_as(users(:one))
    post = create_post(title: "A")

    get "/cs-studio/mind_graph", params: { post: post.id }

    assert_select "[data-mind-graph-focus] a[aria-label='Depth 2']", text: "2"
    assert_select "[data-mind-graph-focus] span[aria-current='true']", text: /\ADepth\s+1\z/ do
      assert_select "span.sr-only", text: "Depth"
    end
    assert_select "[data-mind-graph-focus] [aria-current]", count: 1
    assert_select "[data-mind-graph-focus] [role], [data-mind-graph-focus] [aria-disabled], [data-mind-graph-focus] span[aria-label]", count: 0
  end

  # The canvas's name as the server wrote it rides beside it, for the
  # controller to put back on a page Turbo restored (the script writes the
  # counts into `aria-label`).
  test "the canvas carries its own name twice: as its name, and for the reset" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "canvas[aria-label='Post relationship graph'][data-label='Post relationship graph']"
  end

  test "the search has a live region that stays in the page, apart from the list of links" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "[data-mind-graph-search] p[data-mind-graph-status][role=status]:not([hidden]):empty"
    assert_select "[data-mind-graph-results][role]", count: 0
    assert_select "[data-mind-graph-results] [data-mind-graph-status]", count: 0
  end

  # Loading, a failure and the cap's sentences are written by the script into
  # this region; `role="status"` (a polite live region) is what gets them
  # announced.
  test "the notice over the canvas is a polite live region" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "[data-admin--mind-graph-target='notice'][role='status']", count: 1
  end

  test "zoom in, zoom out and Fit all are buttons beside the canvas" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    { "Zoom in" => "zoomIn", "Zoom out" => "zoomOut", "Fit all" => "fit" }.each do |label, action|
      assert_select "button[type=button][data-action='admin--mind-graph##{action}'][aria-label='#{label}']"
    end
  end
end
