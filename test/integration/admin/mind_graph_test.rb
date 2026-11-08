require "test_helper"

# The mind graph's page: a frame -- heading,
# legend, filter, an empty canvas -- with NO graph data in it. The
# `admin--mind-graph--graph` controller fetches the data from the URL the page names
# (`test/integration/admin/mind_graph_data_test.rb` covers that endpoint) and
# draws it (`test/system/admin/mind_graph_*_test.rb`). Same session gate as every
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

  # The selection card's links are filled into templates the route
  # helpers built: the placeholders arrive literally, for the script to
  # replace with a URL-encoded id or name, and no path is written in JavaScript.
  test "the card's URL templates and the type labels ride on the element" do
    sign_in_as(users(:one))
    create_post(title: "A", content_type: "resume_entry")
    root_page

    get "/cs-studio/mind_graph"

    assert_select "[data-controller='admin--mind-graph--graph'][data-post-focus-url='/cs-studio/mind_graph?post=__ID__'][data-tag-focus-url='/cs-studio/mind_graph?tag=__ID__'][data-tag-posts-url='/cs-studio/posts?tag=__NAME__']"
    # A post's notes for its card: the route takes digits
    # only, so the template is built for id 0 and the segment swapped.
    assert_select "[data-controller='admin--mind-graph--graph'][data-post-notes-url='/cs-studio/notes/post/__ID__/threads']"
    # The list's two reads: the posts no page lists, and
    # the posts behind one of a page's "+N more" pills, by its page and target.
    element = css_select("[data-controller='admin--mind-graph--graph']").first
    assert_equal "/cs-studio/mind_graph/unlisted", element["data-unlisted-url"]
    assert_equal "/cs-studio/mind_graph/listed?page=__ID__&target=__TARGET__", element["data-listed-url"]
    labels = JSON.parse(css_select("[data-controller='admin--mind-graph--graph']").first["data-type-labels"])
    assert_equal({ "resume_entry" => ContentTypes.fetch("resume_entry").label }, labels)
    assert_select "[data-mind-graph-card][hidden]:empty"
    assert_select "[data-mind-graph-tooltip][hidden]:empty"
  end

  # A page's card and the graph that opens around Home
  # (decision 6): four more addresses, built here by the route helpers.
  test "the page's templates ride on the element, built by the route helpers" do
    sign_in_as(users(:one))
    create_page(title: "About")

    get "/cs-studio/mind_graph", params: { locale: "de" }
    element = css_select("[data-controller='admin--mind-graph--graph']").first

    assert_equal "/cs-studio/mind_graph?locale=de&page=__ID__", element["data-page-focus-url"]
    assert_equal "/cs-studio/notes/page/__ID__/threads?locale=de", element["data-page-notes-url"]
    assert_equal "/cs-studio/mind_graph/data?locale=de&page=__ID__", element["data-open-url"]
    assert_equal "/cs-studio/mind_graph/data?everything=1&locale=de", element["data-everything-url"]
    assert_nil element["data-opened-lines"], "the script's to write, once the data has said where to open"
  end

  # "Show everything" is not remembered: it is no parameter of the page, so
  # no address asks for it and a reload opens a large site around Home
  # again. Only the data read takes it.
  test "everything is no parameter of the page: the data url is the same with it" do
    sign_in_as(users(:one))
    create_page(title: "About")

    get "/cs-studio/mind_graph", params: { everything: "1", lines: "3412" }

    element = css_select("[data-controller='admin--mind-graph--graph']").first
    assert_equal "/cs-studio/mind_graph/data", element["data-url"]
    assert_nil element["data-opened-lines"]
    # Searched where a figure or the choice could be written: the addresses
    # the script reads and the bar. (Not the whole page: an asset's digest
    # may hold any digits.)
    addresses = %w[data-url data-open-url data-everything-url data-page-focus-url data-listed-url].to_h { |name| [ name, element[name] ] }
    assert_empty addresses.select { |_name, value| value.match?(/3412|lines/) }
    assert_equal %w[data-everything-url], addresses.select { |_name, value| value.include?("everything") }.keys, "only the address Show everything reads asks for everything"
    assert_no_match(/3412/, css_select("[data-mind-graph-opened]").first.to_s)
  end

  # The bar of the view the 3,000-line rule opened: in the page from the
  # start, hidden and empty of any figure, where a focused view has its bar.
  # The script shows it; "Show everything" is a button, since it changes
  # what this page shows and leads nowhere.
  test "the whole graph's page holds the hidden bar with Show everything as a button, and a focused view has none" do
    sign_in_as(users(:one))
    page = create_page(title: "About")

    get "/cs-studio/mind_graph"

    assert_select "[data-controller='admin--mind-graph--graph'] p[data-mind-graph-opened][hidden]" do
      assert_select "span[data-mind-graph-opened-line]:empty", count: 1
      assert_select "button[type=button][data-mind-graph-everything][data-action='admin--mind-graph--graph#showEverything']", text: "Show everything", count: 1
      assert_select "a", count: 0
    end

    get "/cs-studio/mind_graph", params: { page: page.id }
    assert_select "[data-mind-graph-opened]", count: 0
    assert_select "[data-mind-graph-focus] a", text: "Whole graph"
  end

  # The chips and the card's Close are the shared components' markup, which
  # the scripts clone from one template inside the graph's element. A
  # template's content is no part of the document: the page's text, its Tab
  # order and the controller's `reset` never meet it.
  test "the parts template is inside the graph's element, once" do
    sign_in_as(users(:one))
    create_post(title: "Alpha")

    get "/cs-studio/mind_graph"

    assert_select "template[data-mind-graph-parts]", count: 1
    assert_select "[data-controller='admin--mind-graph--graph'] template[data-mind-graph-parts]", count: 1
  end

  # A retired type, one the registry does not hold, has no label to send: the card shows
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
    assert_equal({ "one" => "%{figure} tag", "other" => "%{figure} tags" }, messages["mind_graph.script.card.tags"])
    assert_equal({ "one" => "Release %{count} pinned", "other" => "Release %{count} pinned" }, messages["mind_graph.script.release_pinned"])
    assert_equal "%{title}: post, %{figure} connections. Shows it in the graph.", messages["mind_graph.script.list.select_post"]["other"]
    assert_equal "Posts · %{count}", messages["mind_graph.script.list.posts"]
    # The list's own words, verbatim.
    assert_equal [ "Not listed on any page", "not in view", "Open in Posts →", "The list couldn't be loaded.", "Try again" ],
                 messages.values_at(*%w[unlisted not_in_view open_in_posts failed try_again].map { |key| "mind_graph.script.list.#{key}" })
    assert_equal "%{title}, %{type} post, not in view. Activate to add it to the graph.", messages["mind_graph.script.list.add_post"]
    assert_equal "%{title}, %{type}, retired type, not in view. Activate to add it to the graph.", messages["mind_graph.script.list.add_retired_post"]
    assert_equal [ "Pages · %{count}", "Tags · %{count}", "Post types · %{count}" ], messages.values_at("mind_graph.script.list.pages", "mind_graph.script.list.tags", "mind_graph.script.list.types")
    assert_equal({ "one" => "%{title}: post type, %{figure} post. Shows it in the graph.", "other" => "%{title}: post type, %{figure} posts. Shows it in the graph." }, messages["mind_graph.script.list.select_type"])
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
    # The words verbatim: a page's card, the chip's second part and the
    # whole chip for a screen reader.
    assert_equal [ "Open page", "Change scheduled %{date}", "Live, unpublished changes", "Live, change scheduled %{date}" ],
                 messages.values_at(*%w[open_page status.change_scheduled status.live_with_changes status.live_change_scheduled].map { |key| "mind_graph.script.card.#{key}" })
    # A list row's name says its chips' own words, from the chips' own keys.
    chip_words = %w[components.ui.status_chip.labels.draft components.ui.status_chip.labels.scheduled components.ui.unpublished_chip.label]
    assert_equal [ "Draft", "Scheduled", "Unpublished changes" ], messages.values_at(*chip_words)
    assert_equal chip_words.map { |key| I18n.t("admin.#{key}") }, messages.values_at(*chip_words)
    assert_equal "%{title}, %{state}", messages["mind_graph.script.list.stated"]
    # A page whose parent is not drawn says the path it stands under.
    assert_equal [ "%{path}", "%{title}, under %{path}" ], messages.values_at("mind_graph.script.list.ancestors", "mind_graph.script.list.under")
    assert_equal [ { "one" => "%{figure} child page", "other" => "%{figure} child pages" }, { "one" => "lists %{figure} post", "other" => "lists %{figure} posts" } ],
                 messages.values_at("mind_graph.script.card.child_pages", "mind_graph.script.card.lists_posts")
    # A pill's row is named with its visible words first ("+92 more: …"), so
    # that someone who says what they see names it (WCAG 2.5.3).
    assert_equal [ true, true ], messages["mind_graph.script.list.more_row"].values_at("one", "other").map { |name| name.start_with?("%{words}: ") }
    assert_equal %w[all_posts capped capped_local card.child_pages card.focus card.lists_posts card.notes.add card.notes.deleted_user card.notes.failed card.notes.label card.notes.label_page card.notes.more
                    card.notes.replies card.notes.sending card.notes.title card.notes.unread card.open_page card.open_post card.pin card.post_type card.related card.show_tagged
                    card.status.change_scheduled card.status.live_change_scheduled card.status.live_with_changes
                    card.tag card.tag_posts card.tags card.unpin isolated isolated_only legend.toggle
                    list.absent_post list.absent_retired_post list.add_post list.add_retired_post list.ancestors list.back list.empty list.failed list.more_heading list.more_row list.not_in_view list.open_in_posts list.pages list.posts
                    list.search_site list.search_site_heading list.select_page list.select_post list.select_tag list.select_type list.stated
                    list.tags list.try_again list.types list.under list.unlisted list.unlisted_none load_failed loading more no_connections opened.everything_name opened.line
                    release_pinned retired_type retry search.failed search.groups.page search.groups.post search.groups.tag search.none
                    summary.all_hidden summary.around_home summary.connections summary.everything summary.hidden.page summary.hidden.post summary.hidden.tag summary.hidden.type
                    summary.hidden_lines.lists summary.hidden_lines.related summary.hidden_lines.tag summary.hidden_lines.tree summary.local summary.more summary.none_yet summary.nothing
                    summary.pages summary.pair summary.posts summary.posts_of summary.series summary.site summary.tags summary.types summary.whole worker_failed].map { |key| "mind_graph.script.#{key}" },
                 messages.keys.grep(/\Amind_graph/).sort
  end

  # The tree column holds the list's head, the find field over the list's
  # tree, and the list's region, empty but for its hidden last line; the
  # graph's box holds the legend's row and the canvas, then the template of
  # what the scripts clone. "Release N pinned" is hidden until something is
  # pinned, and there is no collapsed list of links under the canvas.
  test "the column holds the list's head, its find field and its region; the box holds the legend and the canvas; nothing is pinned" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "aside#tree-column.admin-shell__tree--fill" do
      assert_select "> div:nth-of-type(1) > h2", text: "Pages, posts and tags"
      assert_select "> div:nth-of-type(1) > button.admin-tree-hide[aria-controls='tree-column']", text: "Hide list"
      assert_select "> div[role=search] input[type=search][aria-controls='mind-graph-tree'][placeholder='Find a page, post or tag']"
      assert_select "> [data-mind-graph-list].admin-shell__tree-region[role='region'][aria-label='Pages, posts, tags and post types in this graph']" do
        assert_select "> *", count: 1
        assert_select "> [data-mind-graph-search-site][hidden][data-url^='/cs-studio/mind_graph/search'] > button:empty", count: 1
      end
    end
    assert_select "[data-controller='admin--mind-graph--graph'] [data-mind-graph-list], [data-controller='admin--mind-graph--graph'] input[type=search]", count: 0
    # One column of three parts (the bar of the view a large site opens in,
    # the legend's row, the canvas), and the template of what the scripts
    # clone, which is no part of the document.
    assert_select "[data-controller='admin--mind-graph--graph'] > :not(template)", count: 3
    assert_select "[data-controller='admin--mind-graph--graph'] > template:last-child[data-mind-graph-parts]", count: 1
    assert_select "[data-controller='admin--mind-graph--graph'] > :nth-child(1)[data-mind-graph-opened][hidden]"
    assert_select "[data-controller='admin--mind-graph--graph'] > :nth-child(2) [data-mind-graph-legend]"
    assert_select "[data-controller='admin--mind-graph--graph'] > :nth-child(3) canvas"
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
    assert_equal Admin::Ui::ButtonComponent.classes(:primary, size: :small), buttons["primary"]
    assert_equal Admin::Ui::ButtonComponent.classes(:secondary, size: :small), buttons["secondary"]
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
    assert_select "[data-mind-graph-legend], [data-legend-state]", count: 0
    assert_select "[data-controller='admin--mind-graph--graph']", count: 0
    assert_not_includes response.body, "Hidden from them"
  end

  # A graph of pages alone is a graph.
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

  # The list's first folds are the open set Pages reads, as `TreeOpenSet`
  # reads it for this viewer: an entry for a page they do not read, or one in
  # the trash, is left out, and so is junk; the tree's path is the admin path.
  test "the graph's open set is the cookie's, without the pages the viewer does not read" do
    branch = create_page(title: "Branch")
    inside = create_page(title: "Inside", parent: branch)
    outside = create_page(title: "Outside")
    gone = create_page(title: "Gone")
    gone.update_columns(trashed_at: Time.current) # version: none (a test puts a page in the trash) # changes: none (a test puts a page in the trash)
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ branch.id ] })
    cookies[TreeOpenSet::COOKIE] = "#{inside.id}.-#{branch.id}.#{outside.id}.junk.#{gone.id}"

    sign_in_as(users(:author))
    get "/cs-studio/mind_graph"
    element = css_select("[data-controller='admin--mind-graph--graph']").first
    assert_equal "#{inside.id}.-#{branch.id}", element["data-tree-open"], "the pages the viewer reads, in the cookie's order"
    assert_equal "/cs-studio", element["data-tree-open-path"]
    assert_equal Locales.default, element["data-tree-locale"]

    sign_in_as(users(:one))
    get "/cs-studio/mind_graph"
    assert_equal "#{inside.id}.-#{branch.id}.#{outside.id}", css_select("[data-controller='admin--mind-graph--graph']").first["data-tree-open"], "the trash and the junk are left out for everyone"

    # A viewer who reads no page (and a post) is handed no page's fold.
    create_post(title: "Theirs to read")
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ 0 ] })
    sign_in_as(users(:author))
    get "/cs-studio/mind_graph"
    assert_equal "", css_select("[data-controller='admin--mind-graph--graph']").first["data-tree-open"]
  end

  test "with no page and no post at all, 'No pages or posts yet.' instead of an empty canvas" do
    sign_in_as(users(:one))

    get "/cs-studio/mind_graph"

    assert_response :success
    assert_select "[data-mind-graph-empty=no-content]", text: "No pages or posts yet."
    assert_select "[data-controller~='admin--mind-graph--graph']", count: 0
    # Nothing to list either: no tree column, and no top bar button for one.
    assert_select "#tree-column", count: 0
  end

  test "the legend names only the content types of the viewer's posts, plus the keys" do
    sign_in_as(users(:one))
    create_post(title: "A", content_type: "resume_entry")

    get "/cs-studio/mind_graph"

    assert_select "[data-mind-graph-legend] ul[data-legend-keys] [data-legend-type]", count: 1
    assert_select "ul[data-legend-keys] [data-legend-type='resume_entry']", text: /#{ContentTypes.fetch("resume_entry").label}/
    assert_select "ul[data-legend-keys] [data-legend='pinned']", text: /Pinned/
    assert_select "ul[data-legend-keys] [data-legend='notes']", text: /Open notes/
    assert_select "[data-legend='retired']", count: 0
    # The five looks are the legend's own Status group, whatever posts there are.
    assert_select "[data-mind-graph-legend] ul[data-legend-states] [data-legend-state]", count: 5
    assert_not_includes response.body, "Draft or scheduled"
  end

  test "the legend names no content type of a post the viewer can't read" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    create_post(title: "Own").update_column(:author_id, users(:author).id)
    create_post(title: "Theirs", content_type: "resume_entry")
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_select "ul[data-legend-keys] [data-legend-type]", count: 1
    assert_select "[data-legend-type='resume_entry']", count: 0
  end

  test "a post of a type that is no longer registered adds the Retired type entry" do
    sign_in_as(users(:one))
    create_post(title: "A").update_column(:content_type, "gone/thing")

    get "/cs-studio/mind_graph"

    assert_select "ul[data-legend-keys] [data-legend='retired']", text: /Retired type/
    assert_select "[data-legend-type]", count: 0
  end

  # Design answer F6: the toggles replace the radio group
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

  # A kind that can be drawn has its toggle and its key, and no kind the
  # viewer cannot read has one. The matrix of rights: both, posts alone, pages alone, neither.
  def toggles = css_select("label[data-legend-toggle]").map { |label| [ label.parent["data-legend-group"], label["data-legend-toggle"] ].join(":") }

  test "a viewer who reads pages and posts gets all eight toggles" do
    create_post(title: "Theirs")
    create_page(title: "Theirs too")
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_equal %w[nodes:page nodes:post nodes:tag nodes:type lines:tree lines:lists lines:related lines:tag], toggles
  end

  test "a viewer who reads pages and no post gets the toggles of pages, and of the tags pages list" do
    create_post(title: "Hidden from them")
    create_page(title: "Theirs to read")
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_equal %w[nodes:page nodes:tag nodes:type lines:tree lines:lists], toggles
    assert_select "label[data-legend-toggle=tag] canvas[data-swatch=tag]", count: 1
    assert_not_includes response.body, "Hidden from them"
  end

  test "a viewer who reads posts and no page gets the toggles of posts only" do
    create_post(title: "Theirs to read")
    create_page(title: "Hidden from them")
    access_control_grants(:author_pages_read).update!(scope: { "page_ids" => [ 0 ] })
    sign_in_as(users(:author))

    get "/cs-studio/mind_graph"

    assert_equal %w[nodes:post nodes:tag lines:related lines:tag], toggles
    assert_not_includes response.body, "Hidden from them"
  end

  test "someone who holds neither read right is refused, and is shown no toggle" do
    sign_in_as(users(:editor_branch))

    get "/cs-studio/mind_graph"

    assert_response :forbidden
    assert_select "[data-mind-graph-legend], label[data-legend-toggle]", count: 0
  end

  # Status is not a filter: the five looks are a key on the legend's row,
  # inside the graph's element, drawn by the legend's own swatches
  # controller. The screen opens no dialog of its own.
  test "the status looks are in the legend's row, inside the graph's element, and the page holds no status dialog" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "[data-controller='admin--mind-graph--graph'] [data-mind-graph-legend][data-controller='admin--mind-graph--swatches'] [data-legend-section=status] li[data-legend-state]", count: 5
    assert_select "li[data-legend-state] canvas[data-swatch^='state-']", count: 5
    assert_select "[data-legend-section=status] span.text-label", text: "Status"
    assert_select "[data-controller='admin--mind-graph--graph'] dialog, dialog [data-legend-state]", count: 0
    assert_select "[data-mind-graph-legend] button", count: 0
    assert_not_includes response.body, "Status key"
  end

  # The tab order is the column's find field (the column comes before
  # <main>), the filter (the legend's toggles: its keys and status looks are
  # marks, and no stop), the zoom buttons, then the canvas. (A swatch is a
  # canvas too, and no stop: only the graph's own canvas has a `tabindex`.)
  # The buttons sit in the canvas's corner on screen, but they come BEFORE it
  # in the document, which is what the Tab key follows.
  # ("Release N pinned" is first among the buttons, hidden until a node is
  # pinned; a button is named here by its `aria-label`, as a screen reader
  # names it.)
  test "the tab order is the find field, the filter, the zoom buttons, then the canvas" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    # A template's content is not in the document a browser tabs through.
    order = css_select("#tree-column input[type=search], [data-controller='admin--mind-graph--graph'] input[type=checkbox], [data-controller='admin--mind-graph--graph'] button, [data-controller='admin--mind-graph--graph'] canvas[tabindex]")
      .reject { |node| node.ancestors("template").any? }
      .map { |node| node.name == "button" ? (node["aria-label"] || (node["hidden"] ? "hidden" : node.text.strip)) : node.name == "input" ? (node["type"] == "search" ? "search" : node["data-name"]) : node.name }
    # "Show everything" stands in a bar that is hidden until a large site has
    # opened around Home, where a focused view has its bar's links.
    assert_equal [ "search", "Show everything", "Posts", "Tags", "Related", "Shares a tag", "hidden", "Zoom out", "Zoom in", "Fit all", "canvas" ], order
    assert_select "[data-mind-graph-opened][hidden] button", text: "Show everything"
    assert_select "[data-controller='admin--mind-graph--graph'] input[type=search]", count: 0
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

  # The column is the screen's for a full answer only, as the Pages tree
  # is: a frame answer keeps only `#content`, and the column a frame
  # navigation leaves stands.
  test "the global view has no focus bar, and a frame answer draws no column" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"
    assert_select "[data-mind-graph-focus]", count: 0
    assert_select "#tree-column [data-mind-graph-list]", count: 1

    get "/cs-studio/mind_graph", headers: { "Turbo-Frame" => "content" }
    assert_select "[data-controller='admin--mind-graph--graph']", count: 1
    assert_select "#tree-column, [data-mind-graph-list]", count: 0
  end

  # The column comes before <main> in the document, so the Tab key meets
  # the find field first; then (in a local view) the focus bar's links, the
  # filter, the zoom buttons and the canvas. The bar is the first row of the
  # box, above the legend.
  test "in a local view the tab order is the find field, the bar's links, the filter, the zoom buttons, the canvas" do
    sign_in_as(users(:one))
    post = create_post(title: "A")

    get "/cs-studio/mind_graph", params: { post: post.id }

    order = css_select(([ "#tree-column input[type=search]" ] + %w[[data-mind-graph-focus]\ a input[type=checkbox] button canvas[tabindex]].map { |part| "[data-controller='admin--mind-graph--graph'] #{part}" }).join(", "))
      .reject { |node| node.ancestors("template").any? }
      .map { |node| { "button" => node["aria-label"] || (node["hidden"] ? "hidden" : node.text.strip), "canvas" => "canvas" }.fetch(node.name) { node.name == "a" ? "link:#{node.text.strip}" : node["type"] } }
    assert_equal [ "search", "link:2", "link:Whole graph", "checkbox", "checkbox", "checkbox", "checkbox", "hidden", "Zoom out", "Zoom in", "Fit all", "canvas" ], order
  end

  # The list's region is in the column, before the box in the document; it
  # starts empty but for its last line, and the script fills it.
  test "the list stands in the column, before the canvas, and starts empty" do
    sign_in_as(users(:one))
    create_post(title: "A")

    get "/cs-studio/mind_graph"

    assert_select "#tree-column [data-mind-graph-list] > :not([data-mind-graph-search-site])", count: 0
    order = css_select("#tree-column [data-mind-graph-list], [data-controller='admin--mind-graph--graph'] canvas[tabindex], [data-controller='admin--mind-graph--graph'] [data-mind-graph-card]").map(&:name)
    assert_equal %w[div canvas aside], order
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

  # A size is a type token and a radius a radius token: the zoom's labels
  # are `text-small`, its figure a count (`text-count`, with digits of one
  # width), and the group takes the button's radius.
  test "the zoom buttons are 28px high in the small type, the figure a count with even digits, in a group outlined in the field line with the button's radius" do
    sign_in_as(users(:one))
    create_post(title: "A")
    get "/cs-studio/mind_graph"

    assert_select "[role=group][class~='border-field-line'][class~='rounded-button'][class~='text-small'] button[data-action='admin--mind-graph--graph#zoomIn'][class~='h-7']"
    assert_select "[data-mind-graph-zoom][class~='text-count'][class~='tabular-nums']"
    assert_select "[role=group][class*='text-[13px]'], [role=group][class~='rounded-cs'], [data-mind-graph-zoom][class~='text-label']", count: 0
  end
end
