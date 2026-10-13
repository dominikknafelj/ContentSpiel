require "test_helper"

# The mind graph's page (mind graph canvas spec §3.2): a frame -- heading,
# legend, filter, an empty canvas -- with NO graph data in it. The
# `admin--mind-graph--graph` controller fetches the data from the URL the page names
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
    assert_select "[data-controller='admin--mind-graph--graph'][data-url='/cs-studio/mind_graph/data'][data-state='loading']"
    assert_select "[data-controller='admin--mind-graph--graph'][data-worker-url*='mind_graph/layout_worker'][data-d3-url*='d3-force']"
    assert_select "canvas[role='img'][tabindex='0'][aria-label]"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/mind_graph']", text: "Mind graph"
  end

  # The selection card's links (spec §5.3) are filled into templates the route
  # helpers built: the placeholders arrive literally, for the script to
  # replace with a URL-encoded id or name, and no path is written in JavaScript.
  test "the card's URL templates and the type labels ride on the element" do
    sign_in_as(users(:one))
    create_post(title: "A", content_type: "resume_entry")
    root_page

    get "/cs-studio/mind_graph"

    assert_select "[data-controller='admin--mind-graph--graph'][data-post-focus-url='/cs-studio/mind_graph?post=__ID__'][data-tag-focus-url='/cs-studio/mind_graph?tag=__ID__'][data-tag-posts-url='/cs-studio/posts?tag=__NAME__']"
    # A post's notes for its card (notes spec §4.4): the route takes digits
    # only, so the template is built for id 0 and the segment swapped.
    assert_select "[data-controller='admin--mind-graph--graph'][data-post-notes-url='/cs-studio/notes/post/__ID__/threads']"
    # The list's two reads (pages spec §3, §7): the posts no page lists, and
    # the posts behind one of a page's "+N more" pills, by its page and target.
    element = css_select("[data-controller='admin--mind-graph--graph']").first
    assert_equal "/cs-studio/mind_graph/unlisted", element["data-unlisted-url"]
    assert_equal "/cs-studio/mind_graph/listed?page=__ID__&target=__TARGET__", element["data-listed-url"]
    labels = JSON.parse(css_select("[data-controller='admin--mind-graph--graph']").first["data-type-labels"])
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

    assert_equal "{}", css_select("[data-controller='admin--mind-graph--graph']").first["data-type-labels"]
  end

  # The strings the script shows are the server's (docs/reference/i18n.md): a
  # plural rides whole, for the script to choose a form by count.
  test "the script's messages ride on the element" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    messages = JSON.parse(css_select("[data-controller='admin--mind-graph--graph']").first["data-messages"])
    assert_equal "The graph could not be loaded.", messages["mind_graph.script.load_failed"]
    assert_equal({ "one" => "%{figure} other post has no connections yet and isn't shown.", "other" => "%{figure} other posts have no connections yet and aren't shown." }, messages["mind_graph.script.isolated"])
    assert_equal({ "one" => "%{figure} post has no connections yet.", "other" => "%{figure} posts have no connections yet." }, messages["mind_graph.script.isolated_only"])
    assert_equal({ "one" => "%{count} tag", "other" => "%{count} tags" }, messages["mind_graph.script.card.tags"])
    assert_equal({ "one" => "Release %{count} pinned", "other" => "Release %{count} pinned" }, messages["mind_graph.script.release_pinned"])
    assert_equal "%{title}: post, %{count} connections. Shows it in the graph.", messages["mind_graph.script.list.select_post"]["other"]
    assert_equal "Posts · %{count}", messages["mind_graph.script.list.posts"]
    # The design answer's words, verbatim (F4, G5, H7).
    assert_equal [ "Not listed on any page", "not in view", "Open in Posts →", "The list couldn't be loaded.", "Try again" ],
                 messages.values_at(*%w[unlisted not_in_view open_in_posts failed try_again].map { |key| "mind_graph.script.list.#{key}" })
    assert_equal "%{title}, %{type} post, not in view. Activate to add it to the graph.", messages["mind_graph.script.list.add_post"]
    assert_equal "%{title}, %{type}, retired type, not in view. Activate to add it to the graph.", messages["mind_graph.script.list.add_retired_post"]
    assert_equal [ "Pages · %{count}", "Tags · %{count}", "Post types · %{count}" ], messages.values_at("mind_graph.script.list.pages", "mind_graph.script.list.tags", "mind_graph.script.list.types")
    assert_equal({ "one" => "%{title}: post type, %{count} post. Shows it in the graph.", "other" => "%{title}: post type, %{count} posts. Shows it in the graph." }, messages["mind_graph.script.list.select_type"])
    assert_equal [ "Pages", "Posts", "Tags", "No page, post or tag matches." ], messages.values_at(*%w[groups.page groups.post groups.tag none].map { |key| "mind_graph.script.search.#{key}" })
    # Every string of the list and of the search the locale file holds is served.
    %w[list search].each do |part|
      held = I18n.t("admin.mind_graph.script.#{part}").flat_map { |key, value| value.is_a?(Hash) && !value.key?(:other) ? value.keys.map { |inner| "#{key}.#{inner}" } : [ key.to_s ] }
      assert_empty held.map { |key| "mind_graph.script.#{part}.#{key}" } - messages.keys
    end
    assert_equal "Showing the %{shown} nearest of %{total} posts around this one.", messages["mind_graph.script.capped_local"]
    assert_equal "Open notes · %{count}", messages["mind_graph.script.card.notes.title"]
    assert_equal [ "All posts", "+%{count} more", "%{name} (retired)" ], messages.values_at("mind_graph.script.all_posts", "mind_graph.script.more", "mind_graph.script.retired_type")
    assert_equal "Mind graph: %{kinds}, %{connections}.", messages["mind_graph.script.summary.whole"]
    assert_equal({ "one" => "%{figure} more is in the list.", "other" => "%{figure} more are in the list." }, messages["mind_graph.script.summary.more"])
    assert_equal "%{name}, %{count}", messages["mind_graph.script.legend.toggle"]
    # Every sentence of the summary the locale file holds is served: a key
    # added there and forgotten in the view would throw in the script.
    held = I18n.t("admin.mind_graph.script.summary").flat_map { |key, value| value.is_a?(Hash) && !value.key?(:other) ? value.keys.map { |inner| "#{key}.#{inner}" } : [ key.to_s ] }
    assert_empty held.map { |key| "mind_graph.script.summary.#{key}" } - messages.keys
    assert_equal %w[all_posts capped capped_local card.close card.focus card.notes.add card.notes.deleted_user card.notes.failed card.notes.label card.notes.more card.notes.replies card.notes.sending
                    card.notes.title card.notes.unread card.open_post card.pin card.related card.show_tagged card.status.draft card.status.live card.status.scheduled
                    card.tag card.tag_posts card.tags card.unpin isolated isolated_only legend.toggle
                    list.add_post list.add_retired_post list.empty list.failed list.not_in_view list.open_in_posts list.pages list.posts list.select_page list.select_post list.select_tag list.select_type
                    list.tags list.try_again list.types list.unlisted load_failed loading more no_connections
                    release_pinned retired_type retry search.count search.failed search.groups.page search.groups.post search.groups.tag search.none
                    summary.all_hidden summary.around_home summary.connections summary.everything summary.hidden.page summary.hidden.post summary.hidden.tag summary.hidden.type
                    summary.hidden_lines.lists summary.hidden_lines.related summary.hidden_lines.tag summary.hidden_lines.tree summary.local summary.more summary.none_yet summary.nothing
                    summary.pages summary.pair summary.posts summary.posts_of summary.series summary.site summary.tags summary.types summary.whole worker_failed].map { |key| "mind_graph.script.#{key}" },
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

    assert_select "[data-controller='admin--mind-graph--graph'] > *", count: 3
    assert_select "[data-controller='admin--mind-graph--graph'] > :nth-child(1) #mind-graph-search"
    assert_select "[data-controller='admin--mind-graph--graph'] > :nth-child(2) canvas"
    assert_select "[data-controller='admin--mind-graph--graph'] > :nth-child(3)[data-mind-graph-list][role='region'][aria-label='Pages, posts, tags and post types in this graph']:empty"
    assert_select "details", count: 0
    assert_select "button[data-mind-graph-release][hidden][data-action='admin--mind-graph--graph#releasePinned']:empty"
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

    element = css_select("[data-controller='admin--mind-graph--graph']").first
    buttons = JSON.parse(element["data-button-classes"])
    assert_equal "#{Admin::Ui::ButtonComponent::SMALL_CLASS} #{Admin::Ui::ButtonComponent::VARIANT_CLASSES[:primary]}", buttons["primary"]
    assert_equal "#{Admin::Ui::ButtonComponent::SMALL_CLASS} #{Admin::Ui::ButtonComponent::VARIANT_CLASSES[:secondary]}", buttons["secondary"]
    assert_equal Admin::Ui::ContentTypeDotComponent::FILLED + Admin::Ui::ContentTypeDotComponent::RINGS, JSON.parse(element["data-dot-classes"])
  end

  test "the data url carries the focus, the depth and the editing language" do
    sign_in_as(users(:one))
    with_locales(%w[en de], default: "en")
    post = create_post(title: "A")

    get "/cs-studio/mind_graph", params: { post: post.id, depth: 2, locale: "de" }

    url = css_select("[data-controller='admin--mind-graph--graph']").first["data-url"]
    assert_equal "/cs-studio/mind_graph/data", URI(url).path
    assert_equal({ "post" => post.id.to_s, "depth" => "2", "locale" => "de" }, Rack::Utils.parse_query(URI(url).query))
  end

  test "a tag focus rides in the data url, and a depth other than 1 or 2 is read as 1" do
    sign_in_as(users(:one))
    create_post(title: "A", tags: [ "t" ])
    tag = Tag.find_by!(name: "t")

    get "/cs-studio/mind_graph", params: { tag: tag.id, depth: 7 }

    url = css_select("[data-controller='admin--mind-graph--graph']").first["data-url"]
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

  test "a viewer who can read no post and no page sees 'No pages or posts yet.' and no canvas, however many exist" do
    create_post(title: "Hidden from them")
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    # And no page: a page they read would be something to draw (the next test).
    create_page(title: "A page hidden from them")
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ 0 ] })
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_select "[data-mind-graph-empty=no-content]", text: "No pages or posts yet."
    assert_select "canvas", count: 0
    assert_select "dialog#mind-graph-status-key", count: 0
    assert_select "[data-controller='admin--mind-graph--graph']", count: 0
    assert_not_includes response.body, "Hidden from them"
  end

  # Pages spec §2: a graph of pages alone is a graph.
  test "a viewer who reads pages and no post gets the canvas" do
    create_post(title: "Hidden from them")
    create_page(title: "Theirs to read")
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_response :success
    assert_select "[data-controller='admin--mind-graph--graph'] canvas"
    assert_select "[data-mind-graph-empty]", count: 0
    assert_not_includes response.body, "Hidden from them"
  end

  test "with no page and no post at all, 'No pages or posts yet.' instead of an empty canvas" do
    sign_in_as(users(:one))

    get "/cs-studio/mind_graph"

    assert_response :success
    assert_select "[data-mind-graph-empty=no-content]", text: "No pages or posts yet."
    assert_select "[data-controller~='admin--mind-graph--graph']", count: 0
  end

  test "the legend names only the content types of the viewer's posts, plus the keys" do
    sign_in_as(users(:one))
    create_post(title: "A", content_type: "resume_entry")

    get "/cs-studio/mind_graph"

    assert_select "[data-mind-graph-legend] ul[aria-label='Legend'] [data-legend-type]", count: 1
    assert_select "ul[aria-label='Legend'] [data-legend-type='resume_entry']", text: /#{ContentTypes.fetch("resume_entry").label}/
    assert_select "ul[aria-label='Legend'] [data-legend='pinned']", text: /Pinned/
    assert_select "ul[aria-label='Legend'] [data-legend='notes']", text: /Open notes/
    assert_select "[data-legend='retired']", count: 0
    # The five states are no part of the legend's row: they are the Status key's.
    assert_select "[data-mind-graph-legend] [data-legend-state]", count: 0
    assert_not_includes response.body, "Draft or scheduled"
  end

  test "the legend names no content type of a post the viewer can't read" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    create_post(title: "Own").update_column(:author_id, users(:author).id)
    create_post(title: "Theirs", content_type: "resume_entry")
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_select "ul[aria-label='Legend'] [data-legend-type]", count: 1
    assert_select "[data-legend-type='resume_entry']", count: 0
  end

  test "a post of a type that is no longer registered adds the Retired type entry" do
    sign_in_as(users(:one))
    create_post(title: "A").update_column(:content_type, "gone/thing")

    get "/cs-studio/mind_graph"

    assert_select "ul[aria-label='Legend'] [data-legend='retired']", text: /Retired type/
    assert_select "[data-legend-type]", count: 0
  end

  # Pages spec §6 (design answer F6): the toggles replace the radio group
  # completely, everything on, and "Links in text" is not built.
  test "the legend's toggles are checkboxes in two groups, all on, and the radios are gone" do
    sign_in_as(users(:one))
    create_post(title: "A")
    create_page(title: "Blog")

    get "/cs-studio/mind_graph"

    assert_select "[data-controller='admin--mind-graph--graph'] fieldset[data-legend-group=nodes] input[type=checkbox][name=mind_graph_nodes][checked]", count: 4
    assert_select "[data-controller='admin--mind-graph--graph'] fieldset[data-legend-group=lines] input[type=checkbox][name=mind_graph_lines][checked]", count: 4
    assert_select "input[type=radio]", count: 0
    assert_select "input[name=mind_graph_filter]", count: 0
    assert_not_includes response.body, "Links in text"
  end

  # Pages spec §2: no type the viewer cannot read.
  test "a viewer who reads pages and no post gets the toggles of pages only" do
    create_post(title: "Hidden from them")
    create_page(title: "Theirs to read")
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_equal %w[page type tree lists], css_select("label[data-legend-toggle]").map { |label| label["data-legend-toggle"] }
  end

  test "a viewer who reads posts and no page gets the toggles of posts only" do
    create_post(title: "Theirs to read")
    create_page(title: "Hidden from them")
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ 0 ] })
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_equal %w[post tag related tag], css_select("label[data-legend-toggle]").map { |label| label["data-legend-toggle"] }
    assert_not_includes response.body, "Hidden from them"
  end

  # To someone who reads no page every post is one no page (they read)
  # lists, so "Not listed on any page" would say nothing: the script draws
  # its checkbox only when the element carries the read's address.
  test "the address of the unlisted read is there for a viewer who reads a page, and for no other" do
    create_post(title: "Theirs to read")
    root_page
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"
    assert_select "[data-controller='admin--mind-graph--graph'][data-unlisted-url]"

    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ 0 ] })
    get "/cs-studio/mind_graph"
    assert_select "[data-controller='admin--mind-graph--graph']"
    assert_select "[data-controller='admin--mind-graph--graph'][data-unlisted-url]", count: 0
    assert_not_includes response.body, "mind_graph/unlisted"
  end

  # Third design answers and H6: status is not a filter; its key is a dialog
  # the legend's "Status" link opens. Outside the graph's element, so it is
  # no part of the box's Tab order and the graph's script resets nothing in it.
  test "the status key is in the page once, a closed dialog outside the graph's element" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "dialog#mind-graph-status-key", count: 1
    assert_select "dialog#mind-graph-status-key[open]", count: 0
    assert_select "[data-controller='admin--mind-graph--graph'] dialog", count: 0
    assert_select "dialog#mind-graph-status-key li[data-legend-state]", count: 5
    assert_select "dialog#mind-graph-status-key h2", text: "Status key"
    assert_select "[data-mind-graph-legend] button[data-legend-status][data-admin--ui--dialog-id-param='mind-graph-status-key']", text: "Status"
  end

  # Mind graph canvas spec §5.7: the tab order is the search, the filter (the
  # legend's toggles, then its "Status" button, which is named by its text),
  # the zoom buttons, then the canvas. (A swatch is a canvas too, and no stop:
  # only the graph's own canvas has a `tabindex`.) The buttons sit in the canvas's corner on
  # screen, but they come BEFORE it in the document, which is what the Tab key
  # follows -- as the search does, though on screen it stands on the right.
  # ("Release N pinned" is first among the buttons, hidden until a node is
  # pinned; a button is named here by its `aria-label`, as a screen reader
  # names it.)
  test "the tab order is the search, the filter, the zoom buttons, then the canvas" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    order = css_select("[data-controller='admin--mind-graph--graph'] input[type=search], [data-controller='admin--mind-graph--graph'] input[type=checkbox], [data-controller='admin--mind-graph--graph'] button, [data-controller='admin--mind-graph--graph'] canvas[tabindex]")
      .map { |node| node.name == "button" ? (node["aria-label"] || (node["hidden"] ? "hidden" : node.text.strip)) : node.name == "input" ? (node["type"] == "search" ? "search" : node["data-name"]) : node.name }
    assert_equal [ "search", "Posts", "Tags", "Related", "Shares a tag", "Status", "hidden", "Zoom out", "Zoom in", "Fit all", "canvas" ], order
    assert_equal "search", css_select("[data-controller='admin--mind-graph--graph'] input, [data-controller='admin--mind-graph--graph'] button, [data-controller='admin--mind-graph--graph'] canvas").first["type"]
    assert_select "[data-controller='admin--mind-graph--graph'] canvas[data-swatch][tabindex]", count: 0
    # Nothing is taken out of the Tab order or moved within it; only the card
    # can be handed the focus by the script (`tabindex="-1"`).
    assert_equal [ "aside" ], css_select("[data-controller='admin--mind-graph--graph'] [tabindex]:not([tabindex='0'])").map(&:name)
  end

  test "a focused view names its focus, offers both depths and the way back" do
    sign_in_as(users(:one))
    post = create_post(title: "Alpha")

    get "/cs-studio/mind_graph", params: { post: post.id }

    assert_select "[data-controller='admin--mind-graph--graph'] [data-mind-graph-focus]", text: /Around “Alpha”/
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

  test "a page focus is named as a page, and its depth links keep the page" do
    sign_in_as(users(:one))
    page = create_page(title: "About")

    get "/cs-studio/mind_graph", params: { page: page.id }

    assert_response :success
    assert_select "[data-mind-graph-focus]", text: /Around the page “About”/
    link = css_select("[data-mind-graph-focus] a").find { |a| a.text == "2" }
    assert_equal "/cs-studio/mind_graph", URI(link["href"]).path
    assert_equal({ "page" => page.id.to_s, "depth" => "2" }, Rack::Utils.parse_query(URI(link["href"]).query))
    url = css_select("[data-controller='admin--mind-graph--graph']").first["data-url"]
    assert_equal "/cs-studio/mind_graph/data", URI(url).path
    assert_equal({ "page" => page.id.to_s, "depth" => "1" }, Rack::Utils.parse_query(URI(url).query))

    get "/cs-studio/mind_graph", params: { page: page.id, depth: 2 }
    url = css_select("[data-controller='admin--mind-graph--graph']").first["data-url"]
    assert_equal({ "page" => page.id.to_s, "depth" => "2" }, Rack::Utils.parse_query(URI(url).query))
  end

  # The bar names the focus the data will be drawn around: with a page AND a
  # post in the address, the page.
  test "with a page and a post in the address the bar names the page, and the data url carries both for the same answer" do
    sign_in_as(users(:one))
    page = create_page(title: "About")
    post = create_post(title: "Alpha")

    get "/cs-studio/mind_graph", params: { page: page.id, post: post.id }

    assert_select "[data-mind-graph-focus]", text: /Around the page “About”/
    url = css_select("[data-controller='admin--mind-graph--graph']").first["data-url"]
    assert_equal page.id.to_s, Rack::Utils.parse_query(URI(url).query)["page"]
  end

  test "a page focus outside the viewer's scope, in the trash or unknown is 404" do
    hidden = create_page(title: "Hidden")
    seen = create_page(title: "Seen")
    gone = create_page(title: "Gone")
    gone.update_column(:trashed_at, Time.current)
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ seen.id ] })
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph", params: { page: seen.id }
    assert_response :success
    [ hidden.id, gone.id, 0, "x", [ seen.id ] ].each do |value|
      get "/cs-studio/mind_graph", params: { page: value }
      assert_response :not_found, "expected 404 for page=#{value.inspect}"
      assert_not_includes response.body, "Hidden"
    end
  end

  test "a focus title with markup in it is escaped" do
    sign_in_as(users(:one))
    post = create_post(title: "<b>x</b>")
    page = create_page(title: "<b>x</b>")

    get "/cs-studio/mind_graph", params: { post: post.id }

    assert_select "[data-mind-graph-focus] b", count: 0

    get "/cs-studio/mind_graph", params: { page: page.id }

    assert_select "[data-mind-graph-focus]", text: /Around the page “<b>x<\/b>”/
    assert_select "[data-mind-graph-focus] b", count: 0
  end

  test "the global view has no focus bar, and every view has the search field inside the controller's element" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "[data-mind-graph-focus]", count: 0
    assert_select "[data-controller='admin--mind-graph--graph'] [data-mind-graph-search][data-url^='/cs-studio/mind_graph/search'] input[type=search]#mind-graph-search"
    assert_select "label.sr-only[for=mind-graph-search]", text: "Find a page, post or tag"
    assert_select "[data-mind-graph-search] [data-mind-graph-results][hidden]:empty"
  end

  # Spec §5.7: the search comes first, then (in a local view) the focus bar's
  # links, then the filter, the zoom buttons and the canvas. The bar is the
  # first row of the graph's own column, above the legend.
  test "in a local view the tab order is the search, the bar's links, the filter, the zoom buttons, the canvas" do
    sign_in_as(users(:one))
    post = create_post(title: "A")

    get "/cs-studio/mind_graph", params: { post: post.id }

    order = css_select(%w[input[type=search] [data-mind-graph-focus]\ a input[type=checkbox] button canvas[tabindex]].map { |part| "[data-controller='admin--mind-graph--graph'] #{part}" }.join(", "))
      .map { |node| { "button" => node["aria-label"] || (node["hidden"] ? "hidden" : node.text.strip), "canvas" => "canvas" }.fetch(node.name) { node.name == "a" ? "link:#{node.text.strip}" : node["type"] } }
    assert_equal [ "search", "link:2", "link:Whole graph", "checkbox", "checkbox", "checkbox", "checkbox", "Status", "hidden", "Zoom out", "Zoom in", "Fit all", "canvas" ], order
  end

  # Spec §5.7: the list comes after the canvas (and the card), so it is the
  # last stop -- it can hold two thousand rows; it starts empty, the script
  # fills it.
  test "the list comes last and empty" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "[data-controller='admin--mind-graph--graph'] [data-mind-graph-list]:empty"
    order = css_select("[data-controller='admin--mind-graph--graph'] canvas[tabindex], [data-controller='admin--mind-graph--graph'] [data-mind-graph-card], [data-controller='admin--mind-graph--graph'] [data-mind-graph-list]").map(&:name)
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
  # controller to put back on a page Turbo restored (the script writes its
  # summary of what is in view into `aria-label`).
  test "the canvas carries its own name twice: as its name, and for the reset" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "canvas[role=img][aria-label='Mind graph'][data-label='Mind graph']"
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

    assert_select "[data-admin--mind-graph--graph-target='notice'][role='status']", count: 1
  end

  test "zoom in, zoom out and Fit all are buttons beside the canvas" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    { "Zoom in" => "zoomIn", "Zoom out" => "zoomOut", "Fit all" => "fit" }.each do |label, action|
      assert_select "button[type=button][data-action='admin--mind-graph--graph##{action}'][aria-label='#{label}']"
    end
  end
end
