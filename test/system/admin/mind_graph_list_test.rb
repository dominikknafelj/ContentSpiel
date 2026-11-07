require "application_system_test_case"

class Admin::MindGraphListSystemTest < Admin::MindGraphSystemTestCase
  test "Not listed on any page shows the posts no page lists in place of the groups, and a row that is not in view adds its post once" do
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    listed = create_post(title: "Listed")
    PostRelation.create!(post: listed, related_post: create_post(title: "Also listed"))
    drawn = create_post(title: "Entry drawn", content_type: "resume_entry")
    PostRelation.create!(post: drawn, related_post: listed)
    alone = create_post(title: "Entry alone", content_type: "resume_entry")
    visit admin_mind_graph_path
    await_graph
    assert_nil screen_position(alone), "a post with no connection is not drawn"
    assert_selector "#{GRAPH} [role=status] p", text: "1 other post has no connections yet and isn't shown."
    before = [ graph["data-nodes"], graph["data-edges"] ]
    assert_equal %w[6 4], before, "two pages, three posts and the type; the tree's line, the lists line and two related"

    find("#{LIST} label", text: "Not listed on any page").click

    within(LIST) do
      assert_equal [ "POSTS · 2" ], all("h2").map { |heading| heading.text.upcase }
      assert_selector "button[data-node-id='#{nid(drawn)}']:not([data-not-in-view])", text: "Entry drawn"
      assert_row "Entry drawn: post, 1 connection. Shows it in the graph."
      assert_selector "button[data-node-id='#{nid(alone)}'][data-not-in-view]", text: /Entry alone\s*not in view/
      assert_row "Entry alone, #{ContentTypes.fetch("resume_entry").label.downcase} post, not in view. Activate to add it to the graph."
      assert_no_selector "button", text: "Listed"
    end
    assert_equal before, [ graph["data-nodes"], graph["data-edges"] ], "the canvas is left as it is"

    find("#{LIST} button[data-node-id='#{nid(alone)}']").click
    assert_selector "#{GRAPH}[data-selected='#{nid(alone)}'][data-nodes='7'][data-edges='4']"
    assert_selector "[data-mind-graph-card] h2", text: "Entry alone"
    # It is shown now: the notice no longer counts it among those that aren't.
    assert_no_selector "#{GRAPH} [role=status] p", text: /isn't shown|aren't shown/
    # The page does not know the added post's connections (its row was read
    # with none counted), so its card says nothing of them.
    assert_no_selector "[data-mind-graph-card]", text: /related/i
    assert_selector "[data-mind-graph-card]:focus", wait: 2
    assert_selector "#{LIST} button[data-node-id='#{nid(alone)}']:not([data-not-in-view])[aria-current='true']"
    await_graph
    assert_kind_of Numeric, screen_position(alone)["x"], "the layout has no place for the added post"
    # Its label is measured like every other node's (selected, so it is
    # drawn, and in semibold): a label with no width could not be pressed.
    label = page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.labelBox(#{nid(alone).to_json})")
    assert label && label["right"].is_a?(Numeric) && label["right"] - label["left"] > 20, "the added post's label was not measured: #{label.inspect}"

    # Closing the card gives the focus back to the row that opened it, which
    # is a new element since the rows were drawn again.
    find("[data-mind-graph-card-close]").click
    await_js("document.activeElement?.dataset.nodeId === #{nid(alone).to_json}")

    find("#{LIST} button[data-node-id='#{nid(alone)}']").click
    assert_selector "#{GRAPH}[data-selected='#{nid(alone)}'][data-nodes='7']"
    assert_equal "Posts 4", legend_counts[1], "the count of posts follows what the graph holds"

    # The rows follow the legend: with the posts switched off none is in view.
    toggle "Posts"
    assert_selector "#{LIST} button[data-not-in-view]", count: 2
    # A row that says "Activate to add it to the graph" does: with "Posts"
    # off, a press switches them back on, and selects the post.
    find("#{LIST} button[data-node-id='#{nid(drawn)}']").click
    assert_selector "#{GRAPH} input#mind-graph-nodes-post:checked", visible: :all
    assert_selector "#{GRAPH}[data-selected='#{nid(drawn)}'][data-nodes='7']"
    assert_no_selector "#{LIST} button[data-not-in-view]"
    assert_selector "#{GRAPH} [role=status] p[data-mind-graph-announced]", text: /\AMind graph: 2 pages, 1 post type and 4 posts, 4 connections\. Showing everything\.\z/, visible: :all

    find("#{LIST} label", text: "Not listed on any page").click
    within(LIST) do
      assert_equal [ "PAGES · 2", "POSTS · 4", "POST TYPES · 1" ], all("h2").map { |heading| heading.text.upcase }
      assert_row "#{ContentTypes.fetch("blog").label}: post type, 2 posts. Shows it in the graph."
      assert_selector "button[data-node-id='type-blog'] > canvas[data-mark=type][data-mark-of='#{ContentTypes.fetch("blog").colour_index}'][aria-hidden='true']"
      assert_equal "2", find("button[data-node-id='type-blog']").all("span").last.text, "the number of posts of the type, where a tag's row has its connections"
    end
    # The fourth group is the keyboard's way to a post type's node: its row
    # selects it, as any row does.
    find("#{LIST} button[data-node-id='type-blog']").click
    assert_selector "#{GRAPH}[data-selected='type-blog']"
    assert_selector "[data-mind-graph-card] h2", text: ContentTypes.fetch("blog").label
  end

  # Design answer G5: a read that fails says so in the list, not in a toast,
  # with a small "Try again" button. The stub answers the first request for
  # the unlisted posts itself and hands every other request to the real fetch.
  test "a failed read of the unlisted posts says so in the list, Try again loads them, and Back shows the groups again" do
    create_page(title: "Blog")
    alone = create_post(title: "Alone")
    visit admin_mind_graph_path
    await_graph
    # The first request for the unlisted posts is held until the test lets
    # it go, the second fails, and the third and every other request go to
    # the real fetch.
    page.execute_script(<<~JS)
      const original = window.fetch
      window.realFetch ??= original
      window.unlistedAsked = 0
      window.fetch = (url, options) => {
        if (!String(url).includes("/mind_graph/unlisted")) return original(url, options)
        window.unlistedAsked += 1
        if (window.unlistedAsked === 1) {
          // The held answer says when the page has READ it: its `json()` is
          // wrapped, and the flag is set in the turn the page's own
          // continuation runs in, so what follows it is not a wait.
          return new Promise((resolve) => {
            window.releaseUnlisted = () => original(url, options).then((response) => {
              const json = response.json.bind(response)
              response.json = () => json().then((body) => { window.unlistedRead = body.rows.length; return body })
              resolve(response)
            })
          })
        }
        if (window.unlistedAsked === 2) return Promise.resolve(new Response("", { status: 500 }))
        return original(url, options)
      }
    JS

    # An answer that comes after the filter was let go again is not drawn.
    filter = find("#{LIST} label", text: "Not listed on any page")
    filter.click
    await_js("window.unlistedAsked === 1")
    filter.click
    page.execute_script("window.releaseUnlisted()")
    # NOT "released, then three frames": reading the body can take longer
    # than that on a slow machine, and the assertion below would then pass
    # before the late answer had come at all. The page
    # has read the answer when the flag is set, and has acted on it (or
    # dropped it) in that same turn, before any frame.
    await_js("window.unlistedRead === 1", wait: 10)
    await_frames
    within(LIST) do
      assert_equal [ "PAGES · 2" ], all("h2").map { |heading| heading.text.upcase }, "the late answer replaced the groups"
      assert_no_selector "input[data-mind-graph-unlisted]:checked", visible: :all
    end

    find("#{LIST} label", text: "Not listed on any page").click

    within(LIST) do
      assert_selector "[role=alert] p", text: "The list couldn't be loaded."
      assert_no_selector "button[data-node-id]"
      assert_selector "input[data-mind-graph-unlisted]:checked", visible: :all
      assert_no_selector "button", text: "Back to the list", wait: 0
    end
    # The error line stays through a toggle of the legend: the groups are
    # not drawn under a checkbox that is still ticked.
    toggle "Pages"
    assert_selector "#{GRAPH}[data-nodes='0']"
    toggle "Pages"
    assert_selector "#{GRAPH}[data-nodes='2']"
    within(LIST) do
      assert_selector "[role=alert] p", text: "The list couldn't be loaded."
      assert_no_selector "button[data-node-id]"
      assert_selector "input[data-mind-graph-unlisted]:checked", visible: :all
      press "Try again"
      assert_selector "button[data-node-id='#{nid(alone)}'][data-not-in-view]", text: "Alone"
      assert_no_selector "[role=alert]"
    end
    await_js("document.activeElement?.dataset.nodeId === #{nid(alone).to_json}")
    assert_equal "ready", graph["data-state"], "the graph itself is untouched by the list's failed read"
    assert_no_selector ".admin-toast", wait: 0

    # Whatever the script wrote into the list is the visit's that was left:
    # Back shows the groups, and the filter is off.
    click_frame_link { within("nav[aria-label='Modules']") { click_link "Posts" } }
    page.go_back
    await_graph
    within(LIST) do
      assert_equal [ "PAGES · 2" ], all("h2").map { |heading| heading.text.upcase }
      assert_no_selector "input[data-mind-graph-unlisted]:checked", visible: :all
      assert_selector "input[data-mind-graph-unlisted]", count: 1, visible: :all
    end
  end

  # The graph's own load gives up after fifteen seconds;
  # a read of the list had no limit, so a request that stalled left the box
  # ticked over the groups for good and the designer's line was never said.
  # The stub never answers but honours its signal, as `fetch` does; the
  # fifteen seconds are made 50 milliseconds as in the graph's own test. And
  # while a read is out the rows' region says so (`aria-busy`), which is all
  # the pending state there is: nobody gave words for one.
  test "a read of the list that gets no answer is given up after fifteen seconds and says so in the list, and the list is busy while a read is out" do
    create_page(title: "Blog")
    alone = create_post(title: "Alone")
    visit admin_mind_graph_path
    await_graph
    page.execute_script(<<~JS)
      const original = window.fetch
      window.realFetch ??= original
      window.realTimeout ??= AbortSignal.timeout
      const timeout = AbortSignal.timeout.bind(AbortSignal)
      window.listMode = "hang"
      window.askedFor = []
      // (For the whole window while the mode is "hang": anything else that asked for a timeout then would get 50 ms. Nothing else on this screen asks.)
      AbortSignal.timeout = (milliseconds) => { window.askedFor.push(milliseconds); return timeout(window.listMode === "hang" ? 50 : milliseconds) }
      window.fetch = (url, options) => {
        if (window.listMode === "real" || !String(url).includes("/mind_graph/unlisted")) return original(url, options)
        if (window.listMode === "hang") return new Promise((resolve, reject) => options.signal.addEventListener("abort", () => reject(options.signal.reason)))
        return new Promise((resolve) => { window.releaseList = () => resolve(original(url, options)) })
      }
    JS

    find("#{LIST} label", text: "Not listed on any page").click
    within(LIST) do
      assert_selector "[role=alert] p", text: "The list couldn't be loaded."
      assert_button "Try again"
      assert_selector "input[data-mind-graph-unlisted]:checked", visible: :all
      assert_no_selector "[aria-busy='true']", wait: 0
    end
    assert_equal [ 15_000 ], page.evaluate_script("window.askedFor"), "the read is given fifteen seconds"
    assert_equal "ready", graph["data-state"]

    page.execute_script("window.listMode = 'hold'")
    within(LIST) { press "Try again" }
    assert_selector "#{LIST} [aria-busy='true']"
    page.execute_script("window.listMode = 'real'; window.releaseList()")
    within(LIST) do
      assert_selector "button[data-node-id='#{nid(alone)}'][data-not-in-view]", text: "Alone"
      assert_no_selector "[aria-busy='true']", wait: 0
    end

    # A read that is let go while it is out leaves nothing busy behind.
    page.execute_script("window.listMode = 'hold'")
    filter = find("#{LIST} label", text: "Not listed on any page")
    filter.click
    assert_no_selector "#{LIST} button[data-node-id='#{nid(alone)}']"
    filter.click
    assert_selector "#{LIST} [aria-busy='true']"
    filter.click
    assert_no_selector "#{LIST} [aria-busy='true']"
    assert_equal [ "PAGES · 2" ], within(LIST) { all("h2").map { |heading| heading.text.upcase } }
  end

  test "the list's Pages group is the tree, a page's title and path with markup in them are text in the list, the search and the card" do
    docs = create_page(title: "<b>Docs</b>")
    create_page(title: "Guide", parent: docs)
    visit admin_mind_graph_path
    await_graph

    within(LIST) do
      assert_equal [ "PAGES · 3" ], all("h2").map { |heading| heading.text.upcase }
      assert_equal [ "Home", "<b>Docs</b>", "Guide" ], all("li button span.truncate").map(&:text)
      assert_no_selector "b"
      # A tree for a screen reader too: a page's row is in a list inside its
      # parent's item, three levels deep here.
      assert_selector "ul[role=list] > li > ul[role=list] > li > ul[role=list] > li > button[data-node-id='#{nid(Page.find_by!(parent: docs))}']"
      assert_selector "li > button > canvas[data-mark=page][aria-hidden='true']", count: 3
    end
    assert_marks_drawn LIST
    # In the Tab order the filter's checkbox is the list's first stop, after
    # the canvas, and the rows follow it.
    stops = page.evaluate_script(<<~JS)
      Array.from(document.querySelector(#{GRAPH.to_json}).querySelectorAll("input, button, a[href], canvas[tabindex='0']"))
        .filter((element) => element.checkVisibility() && !element.closest("[hidden]") && (element.tagName === "CANVAS" || element.closest("[data-mind-graph-list]")))
        .map((element) => element.tagName === "CANVAS" ? "canvas" : element.type === "checkbox" ? "checkbox" : "row")
    JS
    assert_equal %w[canvas checkbox row row row], stops

    # A canvas holds colours, not tokens: a row's mark is drawn again when
    # the theme changes, like the graph.
    mark = "document.querySelector(#{"#{LIST} canvas[data-mark=page]".to_json}).toDataURL()"
    before = page.evaluate_script(mark)
    theme = page.evaluate_script("document.documentElement.getAttribute('data-theme')")
    begin
      page.execute_script("document.documentElement.setAttribute('data-theme', #{(theme == "dark" ? "light" : "dark").to_json})")
      await_js("#{mark} !== #{before.to_json}")
    ensure
      page.execute_script("document.documentElement.setAttribute('data-theme', #{theme.to_json})")
    end
    await_js("#{mark} === #{before.to_json}")

    click_node(nid(docs))
    assert_selector "[data-mind-graph-card] h2", text: "<b>Docs</b>"
    assert_no_selector "[data-mind-graph-card] b"
    fill_in "Find a page, post or tag", with: "docs"
    assert_selector "#{GRAPH} [data-search-group=page] a", text: "<b>Docs</b>"
    assert_no_selector "#{GRAPH} [data-mind-graph-results] b"
  end

  # Around a page
  # at depth 2 the twenty newest posts it lists are drawn, each hanging off
  # the hub that brings it in; the rest stand behind "+N more", which hangs
  # off the same hub and opens the list; a row there adds its post, joined
  # to its hub and not to the page.
  test "around a page, more opens the list with the posts that are not drawn, a row adds its post to its hub, and Open in Posts leads there" do
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "resume_entry" })
    posts = 22.times.map { |index| create_post(title: "Entry #{index}", content_type: "resume_entry") }
    posts.each_with_index { |post, index| post.update_columns(published_at: (index + 1).hours.ago) } # version: none (a test sets a time) # changes: none (a test sets a time)
    visit admin_mind_graph_path(page: blog.id, depth: 2)
    await_graph
    assert_selector "[data-mind-graph-focus]", text: "Around the page “Blog”"
    lines = graph["data-edges"].to_i
    assert_equal 23, lines, "the tree line to Home, the lists line to the type, and the hub's faint lines to twenty posts and to more"
    assert_nil screen_position(posts.last)
    assert screen_position("more-type-resume_entry"), "the pill is not drawn"
    assert_selector "#{CANVAS}[aria-label='Mind graph around Blog, depth 2: 2 pages, 1 post type and 20 of 22 posts. 2 more are in the list.']"
    assert_not_includes graph["data-labelled"].split(","), "more-type-resume_entry", "the pill carries its words: it has no label beside it"
    entry = ContentTypes.fetch("resume_entry").label

    click_node("more-type-resume_entry")

    within(LIST) do
      assert_equal [ "MORE FROM #{entry.upcase} · 2" ], all("h2").map { |heading| heading.text.upcase }, "the rows are named by what the pill hangs off"
      assert_selector "section button[data-mind-graph-back]", text: "Back to the list"
      assert_equal [ "Entry 20", "Entry 21" ], all("li button span.truncate").map(&:text)
      assert_selector "button[data-not-in-view]", count: 2
      assert_row "Entry 21, #{entry.downcase} post, not in view. Activate to add it to the graph."
      assert_selector "a[data-mind-graph-posts-link]", text: "Open in Posts →"
      assert_no_selector "input[data-mind-graph-unlisted]:checked", visible: :all
    end
    assert_equal "", graph["data-selected"], "more is not selected"
    assert_no_selector "[data-mind-graph-card]", visible: :visible

    find("#{LIST} button[data-node-id='#{nid(posts.last)}']").click
    assert_selector "#{GRAPH}[data-selected='#{nid(posts.last)}'][data-edges='#{lines + 1}']"
    assert_equal [ "type-resume_entry" ], graph["data-neighbours"].split(","), "the added post is joined to the hub that brings it in, and not to the page"
    within(LIST) { assert_row "Entry 21: post, 1 connection. Shows it in the graph." }
    # The figures are true of what is drawn now: one more post, one fewer behind the pill.
    assert_selector "#{CANVAS}[aria-label='Mind graph around Blog, depth 2: 2 pages, 1 post type and 21 of 22 posts. 1 more is in the list.']"
    # The heading over the rows counts what the pill counts: one figure for "more" on the screen.
    within(LIST) do
      assert_selector "h2", text: /· 1\z/
      assert_equal [ "MORE FROM #{entry.upcase} · 1" ], all("h2").map { |heading| heading.text.upcase }
      assert_selector "li button[data-node-id^='post-']", count: 2
    end
    await_graph
    assert_kind_of Numeric, screen_position(posts.last)["x"], "the layout has no place for the added post"

    # The added line is the hub's, and follows "Lists" as the others do.
    toggle "Lists"
    assert_selector "#{GRAPH}[data-edges='1']"
    toggle "Lists"

    # The way back to the groups: Escape on the canvas clears the selection,
    # and with nothing selected it lets the pill's rows go.
    escape_on_canvas
    assert_selector "#{GRAPH}[data-selected='']"
    within(LIST) { assert_selector "a[data-mind-graph-posts-link]" }
    escape_on_canvas
    within(LIST) do
      assert_equal [ "PAGES · 2", "POSTS · 21", "POST TYPES · 1" ], all("h2").map { |heading| heading.text.upcase }
      assert_no_selector "a[data-mind-graph-posts-link]"
      # The pill's row says what the pill says: one post is still behind it.
      assert_selector "button[data-node-id='more-type-resume_entry'][data-more]", exact_text: "+1 more"
      assert_row "+1 more: 1 more post #{entry} lists, not in view. Activate to show it."
    end

    await_graph
    click_node("more-type-resume_entry")
    click_frame_link "Open in Posts →"
    assert_equal({ "type" => "resume_entry" }, Rack::Utils.parse_query(URI(current_url).query).slice("type", "tag"))
  end

  # Nothing on a canvas
  # can be pressed by a keyboard, and the canvas's name tells a screen reader
  # that "2 more are in the list": each pill has a row there, and Enter on it
  # is a press on the pill. The focus goes to the first of the rows it
  # brings; Escape in them, and "Back to the list" over them, give the groups
  # back with the focus on the pill's row; a read that failed keeps the way
  # back. With "Posts" off a row that says "Activate to add it to the graph"
  # switches them on. The last post added takes the pill, its row and its
  # rows' heading away, and every figure says so.
  #
  # The layout is not waited for until the end: the rows are there with the
  # data, and a post added while the layout still moves must have a place.
  test "a pill's row opens its rows from the keyboard with the focus on the first, Escape and Back to the list return to it, a failed read keeps a way back, a row switches Posts back on, and the last post added takes the pill away" do
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "resume_entry" })
    posts = 22.times.map { |index| create_post(title: "Entry #{index}", content_type: "resume_entry") }
    posts.each_with_index { |post, index| post.update_columns(published_at: (index + 1).hours.ago) } # version: none (a test sets a time) # changes: none (a test sets a time)
    entry = ContentTypes.fetch("resume_entry").label
    pill = "#{LIST} button[data-node-id='more-type-resume_entry']"
    focused = ->(id) { await_js("document.activeElement?.dataset.nodeId === #{id.to_json}") }
    keyboard = page.driver.browser.keyboard
    visit admin_mind_graph_path(page: blog.id, depth: 2)
    assert_selector "#{GRAPH}[data-state='ready']", wait: 15

    assert_selector pill, exact_text: "+2 more"
    within(LIST) do
      assert_row "+2 more: 2 more posts #{entry} lists, not in view. Activate to show them."
      assert_equal %w[type-resume_entry more-type-resume_entry], all("section:last-of-type button").map { |button| button["data-node-id"] }, "the pill's row stands under its hub's"
      assert_equal [ "PAGES · 2", "POSTS · 20", "POST TYPES · 1" ], all("h2").map { |heading| heading.text.upcase }, "and is counted in no heading"
    end

    # The first read fails (the stub answers it and puts the real fetch back).
    page.execute_script(<<~JS)
      const real = window.fetch
      window.realFetch ??= real
      window.fetch = (url, options) => {
        if (!String(url).includes("/mind_graph/listed")) return real(url, options)
        window.fetch = real
        return Promise.resolve(new Response("", { status: 500 }))
      }
    JS
    find(pill).execute_script("this.focus()")
    keyboard.type(:Enter)
    within(LIST) do
      assert_selector "[role=alert] p", text: "The list couldn't be loaded."
      assert_selector "[role=alert] button[data-mind-graph-retry]", text: "Try again"
      assert_selector "[role=alert] button[data-mind-graph-back]", text: "Back to the list"
    end
    await_js("document.activeElement?.hasAttribute('data-mind-graph-retry')")
    keyboard.type(:Escape)
    assert_selector pill
    assert_no_selector "#{LIST} [role=alert]"
    focused.call("more-type-resume_entry")

    keyboard.type(:Enter)
    focused.call(nid(posts[20]))
    within(LIST) do
      assert_equal [ "MORE FROM #{entry.upcase} · 2" ], all("h2").map { |heading| heading.text.upcase }
      assert_equal [ "Entry 20", "Entry 21" ], all("li button span.truncate").map(&:text)
    end
    assert_equal "", graph["data-selected"], "the pill is not selected by its row either"

    keyboard.type(:Escape)
    assert_selector pill
    focused.call("more-type-resume_entry")
    keyboard.type(:Enter)
    focused.call(nid(posts[20]))
    within(LIST) { press "Back to the list" }
    focused.call("more-type-resume_entry")
    keyboard.type(:Enter)
    focused.call(nid(posts[20]))

    # "Posts" off: the pill goes with the posts, its rows stay, and a row
    # that is activated switches the posts back on and adds its post.
    toggle "Posts"
    assert_selector "#{GRAPH} input#mind-graph-nodes-post:not(:checked)", visible: :all
    assert_selector "#{LIST} button[data-not-in-view]", count: 2
    find("#{LIST} button[data-node-id='#{nid(posts[20])}']").click
    assert_selector "#{GRAPH} input#mind-graph-nodes-post:checked", visible: :all
    assert_selector "#{GRAPH}[data-selected='#{nid(posts[20])}']"
    assert_selector "#{CANVAS}[aria-label='Mind graph around Blog, depth 2: 2 pages, 1 post type and 21 of 22 posts. 1 more is in the list.']"
    assert_selector "#{GRAPH} [role=status] p[data-mind-graph-announced]", text: "21 of 22 posts. 1 more is in the list.", visible: :all
    assert_selector "#{LIST} button[data-not-in-view]", count: 1

    # The pill is dragged, which pins it where it is dropped, and hovered.
    escape_on_canvas
    dropped = drag_node("more-type-resume_entry", by: [ 24, 18 ])
    assert_selector "#{GRAPH}[data-pinned='1']"
    assert_selector "#{GRAPH} [data-mind-graph-release]", text: "Release 1 pinned"
    page.driver.browser.mouse.move(x: dropped["x"], y: dropped["y"])
    await_js("document.querySelector(#{GRAPH.to_json}).dataset.hovered === 'more-type-resume_entry'")

    # The last one: nothing is behind the pill, so the pill, its row and its
    # rows go, and the list is the groups again. A SPENT PILL IS NOTHING: no
    # pin (nothing is left to release), and where it stood no hover, no
    # press, no label and no row; no count holds it.
    find("#{LIST} button[data-node-id='#{nid(posts[21])}']").click
    assert_selector "#{GRAPH}[data-selected='#{nid(posts[21])}'][data-edges='24'][data-pinned='0']"
    assert_no_selector "#{GRAPH} [data-mind-graph-release]", wait: 0
    assert_equal "25", graph["data-nodes"], "two pages, the hub and twenty-two posts: the pill is not among what is drawn"
    assert_selector "#{CANVAS}[aria-label='Mind graph around Blog, depth 2: 2 pages, 1 post type and 22 posts.']"
    within(LIST) do
      assert_equal [ "PAGES · 2", "POSTS · 22", "POST TYPES · 1" ], all("h2").map { |heading| heading.text.upcase }
      assert_no_selector "button[data-more]"
      assert_no_selector "button[data-mind-graph-back]"
      assert_selector "button[data-node-id='#{nid(posts[21])}'][aria-current='true']"
    end
    await_graph
    assert_nil screen_position("more-type-resume_entry"), "a pill that stands for nothing is not drawn"
    assert_nil page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.markBox('more-type-resume_entry')")
    assert_not_includes graph["data-labelled"].split(","), "more-type-resume_entry"
    mouse = page.driver.browser.mouse
    mouse.move(x: dropped["x"] + 1, y: dropped["y"] + 1)
    await_frames
    assert_not_equal "more-type-resume_entry", graph["data-hovered"], "where the pill was dropped nothing of it is hovered"
    lines = graph["data-edges"]
    mouse.click(x: dropped["x"], y: dropped["y"])
    await_frames
    assert_not_equal "more-type-resume_entry", graph["data-selected"]
    within(LIST) { assert_equal [ "PAGES · 2", "POSTS · 22", "POST TYPES · 1" ], all("h2").map { |heading| heading.text.upcase }, "a press where it stood opens no rows" }
    assert_equal lines, graph["data-edges"]
    assert_equal "Posts 22", legend_counts[1]
    places = page.evaluate_script("#{posts.last(2).map { |post| nid(post) }.to_json}.map((id) => document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(id)).flatMap((at) => [ at.x, at.y ])")
    assert places.size == 4 && places.all? { |value| value.is_a?(Numeric) && value.finite? }, "an added post has no place: #{places.inspect}"
  end

  # Design answer H1: ONE PILL PER TARGET. A page with two list blocks has
  # two pills, each on its own hub or tag, each with its own posts, its own
  # row in the list and its own way to Posts.
  test "a page with two list blocks has two pills, each with its own row, its own posts and its own way to Posts, and a post a tag brings in is joined to that tag" do
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "tag" => "pill" })
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 1, settings: { "content_type" => "resume_entry" })
    stray = create_post(title: "Stray") # no page lists it: a plain post with no tag
    pills = 15.times.map { |index| create_post(title: "Pill #{index}", tags: [ "pill" ]) }
    entries = 15.times.map { |index| create_post(title: "Entry #{index}", content_type: "resume_entry") }
    pills.each_with_index { |post, index| post.update_columns(published_at: (2 * index + 1).hours.ago) }   # version: none (a test sets a time) # changes: none (a test sets a time)
    entries.each_with_index { |post, index| post.update_columns(published_at: (2 * index + 2).hours.ago) } # version: none (a test sets a time) # changes: none (a test sets a time)
    tag = "tag-#{Tag.find_by!(name: "pill").id}"
    entry = ContentTypes.fetch("resume_entry").label

    with_reduced_motion do
      visit admin_mind_graph_path(page: blog.id, depth: 2)
      await_graph

      # The twenty newest are ten of each; five of each are left out.
      [ "more-#{tag}", "more-type-resume_entry" ].each { |id| assert screen_position(id), "#{id} is not drawn" }
      assert_selector "#{CANVAS}[aria-label='Mind graph around Blog, depth 2: 2 pages, 1 post type, 20 of 30 posts and 1 tag. 10 more are in the list.']"
      within(LIST) do
        assert_equal [ [ "more-#{tag}", "+5 more" ], [ "more-type-resume_entry", "+5 more" ] ], all("button[data-more]").map { |button| [ button["data-node-id"], button.text ] }
        assert_row "+5 more: 5 more posts pill lists, not in view. Activate to show them."
        assert_row "+5 more: 5 more posts #{entry} lists, not in view. Activate to show them."
      end

      # A pill's read that fails says so with a way back, and what clears a
      # press on the canvas clears this too: Escape there, nothing selected.
      # (The stub fails the one read and puts the real fetch back.)
      page.execute_script(<<~JS)
        const real = window.fetch
      window.realFetch ??= real
        window.fetch = (url, options) => {
          if (!String(url).includes("/mind_graph/listed")) return real(url, options)
          window.fetch = real
          return Promise.resolve(new Response("", { status: 500 }))
        }
      JS
      click_node("more-type-resume_entry")
      assert_selector "#{LIST} [role=alert] button[data-mind-graph-back]", text: "Back to the list"
      toggle "Tree"
      toggle "Tree"
      assert_selector "#{LIST} [role=alert] p", text: "The list couldn't be loaded."
      escape_on_canvas
      assert_no_selector "#{LIST} [role=alert]"
      assert_selector "#{LIST} button[data-more]", count: 2

      click_node("more-type-resume_entry")
      within(LIST) do
        assert_selector "button[data-mind-graph-back]"
        assert_equal [ "MORE FROM #{entry.upcase} · 5" ], all("h2").map { |heading| heading.text.upcase }
        assert_equal entries.last(5).map(&:title), all("li button span.truncate").map(&:text)
        assert_equal({ "type" => "resume_entry" }, Rack::Utils.parse_query(URI(find("a[data-mind-graph-posts-link]")[:href]).query).slice("type", "tag"))
      end

      click_node("more-#{tag}")
      within(LIST) do
        assert_selector "h2", text: /more from pill/i
        assert_equal [ "MORE FROM PILL · 5" ], all("h2").map { |heading| heading.text.upcase }
        assert_equal pills.last(5).map(&:title), all("li button span.truncate").map(&:text), "the other pill's posts, and none of the first's"
        assert_equal({ "tag" => "pill" }, Rack::Utils.parse_query(URI(find("a[data-mind-graph-posts-link]")[:href]).query).slice("type", "tag"))
      end
      lines = graph["data-edges"].to_i
      find("#{LIST} button[data-node-id='#{nid(pills.last)}']").click
      assert_selector "#{GRAPH}[data-selected='#{nid(pills.last)}'][data-edges='#{lines + 1}']"
      assert_equal [ tag ], graph["data-neighbours"].split(","), "a post a tag brings in gets its own line to that tag"
      # Each pill counts its own: the tag's stands for one fewer, the type's for as many as before.
      assert_selector "#{CANVAS}[aria-label='Mind graph around Blog, depth 2: 2 pages, 1 post type, 21 of 30 posts and 1 tag. 9 more are in the list.']"
      within(LIST) do
        assert_selector "h2", text: /· 4\z/
        assert_equal [ "MORE FROM PILL · 4" ], all("h2").map { |heading| heading.text.upcase }, "the heading follows its own pill, and the other pill's count is untouched"
      end
      within(LIST) { press "Back to the list" }
      within(LIST) do
        assert_equal [ [ "more-#{tag}", "+4 more" ], [ "more-type-resume_entry", "+5 more" ] ], all("button[data-more]").map { |button| [ button["data-node-id"], button.text ] }
      end
      # A post the person adds from "Not listed on any page" is in view and is
      # not one the page lists: it is counted beside them, so 21 and 9 still
      # make the page's 30.
      find("#{LIST} label", text: "Not listed on any page").click
      find("#{LIST} button[data-node-id='#{nid(stray)}'][data-not-in-view]").click
      assert_selector "#{GRAPH}[data-selected='#{nid(stray)}']"
      assert_selector "#{CANVAS}[aria-label='Mind graph around Blog, depth 2: 2 pages, 1 post type, 21 of 30 posts, 1 post and 1 tag. 9 more are in the list.']"
      await_graph
    end
  end

  # Nothing on a canvas takes focus, so every node
  # the graph draws is also a row in the list beside it -- grouped, counted,
  # best-connected first -- and the list follows the filter. A row is a button
  # and says in its name what it is and what pressing it does. The collapsed
  # list of links that stood under the canvas is gone.
  test "the list beside the canvas holds every drawn node as a row, grouped and counted, and follows the filter" do
    a = create_post(title: "Alpha", tags: [ "shared" ])
    create_post(title: "Beta", tags: [ "shared" ])
    c = create_post(title: "Gamma")
    PostRelation.create!(post: a, related_post: c)
    visit admin_mind_graph_path
    await_graph

    assert_no_selector "#{GRAPH} details"
    assert_no_text "List of posts and tags in this graph"
    within(LIST) do
      # (The headings are in the upper-case label style.)
      assert_equal [ "POSTS · 3", "TAGS · 1" ], all("h2").map { |heading| heading.text.upcase }
      assert_equal [ "Alpha", "Beta", "Gamma", "shared" ], all("li button span.truncate").map(&:text), "posts then tags, best-connected first, equals by title"
      assert_equal %w[2 1 1 2], all("li button span:last-child").map(&:text), "each row's number of connections"
      assert_row "Alpha: post, 2 connections. Shows it in the graph."
      assert_row "Gamma: post, 1 connection. Shows it in the graph."
      assert_row "shared: tag, 2 connections. Shows it in the graph."
      assert_selector "li button > span[aria-hidden='true']", count: 4
      assert_no_selector "a", visible: :all
      # Nobody reads a page here (there is none), so "Not listed on any
      # page" would say nothing: the filter is not offered.
      assert_no_selector "input, label", visible: :all
    end

    toggle "Tags"
    await_graph
    within(LIST) do
      assert_equal [ "POSTS · 3" ], all("h2").map { |heading| heading.text.upcase }
      assert_equal %w[Alpha Beta Gamma], all("li button span.truncate").map(&:text)
    end
  end

  test "the list holds exactly the nodes a capped graph draws" do
    create_post(title: "A")
    visit_screen admin_tags_path
    stub_graph_data(CAPPED_GRAPH)

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_graph

    within(LIST) do
      assert_selector "li", count: 2
      assert_equal %w[One Two], all("li button span.truncate").map(&:text)
    end
  end

  # A row does to the graph what a click on the node does, and brings the
  # node to the middle of the canvas. It does not navigate: the card does.
  test "a row selects its node, centres the canvas on it and marks itself; it does not navigate" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path
    await_graph
    box = canvas_box
    centre = [ (box[0] + box[2]) / 2, (box[1] + box[3]) / 2 ]
    from = screen_position(a)
    assert_operator Math.hypot(from["x"] - centre[0], from["y"] - centre[1]), :>, 20, "the node is in the middle already: nothing to see"
    zoom = graph["data-zoom"]

    within(LIST) { find("button", text: "Alpha").click }

    assert_equal nid(a), graph["data-selected"]
    await_js("(() => { const p = document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{nid(a).to_json}); return Math.abs(p.x - #{centre[0]}) < 2 && Math.abs(p.y - #{centre[1]}) < 2 })()")
    assert_equal zoom, graph["data-zoom"], "centring changed the zoom"
    assert_selector "#{LIST} button[aria-current='true']", text: "Alpha", count: 1
    assert_selector "[data-mind-graph-card] h2", text: "Alpha"
    await_frames
    assert_card_beside(a, side: "right")
    assert_current_path admin_mind_graph_path

    # Another row moves the mark; clearing the selection takes it away.
    within(LIST) { find("button", text: "Beta").click }
    assert_selector "#{LIST} button[aria-current='true']", text: "Beta", count: 1
    escape_on_canvas
    assert_no_selector "#{LIST} button[aria-current]"
  end

  # The other direction: a node selected on the canvas has its row marked, and
  # the list scrolls -- by itself, not the page -- until the row is in view.
  test "selecting a node on the canvas marks its row and scrolls the list to it" do
    posts = 70.times.map { |i| create_post(title: format("Post %02d", i)) }
    posts.each_cons(2) { |a, b| PostRelation.create!(post: a, related_post: b) }
    visit admin_mind_graph_path
    await_graph
    # The last row: one of the chain's two ends, which have one connection.
    last = posts.last
    row_in_view = "(() => { const list = document.querySelector(#{LIST.to_json}).getBoundingClientRect(); const row = document.querySelector(#{LIST.to_json} + ' button[data-node-id=\"#{nid(last)}\"]').getBoundingClientRect(); return row.top >= list.top - 1 && row.bottom <= list.bottom + 1 })()"
    assert_not page.evaluate_script(row_in_view), "the row is in view before anything is selected: the list is not long enough for this test"
    scrolled = page.evaluate_script("window.scrollY")

    click_node(last)

    assert_selector "#{LIST} button[aria-current='true'][data-node-id='#{nid(last)}']"
    await_js(row_in_view)
    assert_equal scrolled, page.evaluate_script("window.scrollY"), "the page scrolled, not the list"
  end

  # Hovering a row lights its node up as the pointer on the node would.
  test "hovering a row of the list highlights its node on the canvas" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path
    await_graph
    point = screen_position(a)
    ring_before = pixel_at(point["x"] - 9.5, point["y"])

    find("#{LIST} button", text: "Alpha").hover

    await_js("document.querySelector(#{GRAPH.to_json}).dataset.hovered === '#{nid(a)}'")
    assert_not_equal ring_before, pixel_at(point["x"] - 9.5, point["y"]), "no ring round the node whose row is hovered"
    assert_equal "", graph["data-selected"].to_s

    find("h1", text: "Mind graph").hover
    await_js("document.querySelector(#{GRAPH.to_json}).dataset.hovered === ''")
  end

  # The keyboard's whole way: a row is reached by Tab (it is a button), Enter
  # selects its node and hands the focus to the card; Tab then walks the card
  # as it reads -- the note's field before "Open post" (the notes handoff's
  # decision 12) -- Enter on the card opens the post, and Escape gives the
  # focus back to the row.
  test "the list is the keyboard path: Enter on a row opens the node's card and moves the focus to it, and Enter there opens the post" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path
    await_graph

    # Real keys, on an element focused by script: Cuprite's `send_keys` CLICKS
    # an element that is not focused, and the click would do what Enter is
    # here to show.
    find("#{LIST} button", text: "Alpha").execute_script("this.focus()")
    page.driver.browser.keyboard.type(:Enter)

    assert_equal nid(a), graph["data-selected"]
    assert page.evaluate_script("document.activeElement === document.querySelector('[data-mind-graph-card]')"), "the focus did not move to the card"
    assert_equal "mind-graph-card-title", find("[data-mind-graph-card]")["aria-labelledby"], "the card is not named by its title"
    # Tab meets the card in its reading order: the notes' field, then the actions.
    assert_selector "[data-mind-graph-card] textarea"
    page.driver.browser.keyboard.type(:Tab)
    assert_equal "TEXTAREA", page.evaluate_script("document.activeElement.tagName")
    stops = page.evaluate_script("Array.from(document.querySelectorAll('[data-mind-graph-card] :is(a[href], button, textarea)')).filter((stop) => !stop.disabled && stop.getClientRects().length > 0).map((stop) => stop.tagName === 'TEXTAREA' ? 'field' : stop.textContent.trim())")
    assert_operator stops.index("field"), :<, stops.index("Open post")
    assert_equal [ "Open post", "Focus", "Pin", "×" ], stops.last(4)
    page.driver.browser.keyboard.type(:Escape)

    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_equal "Alpha", page.evaluate_script("document.activeElement.querySelector('span.truncate')?.textContent"), "the focus did not go back to the row"

    # Enter on the row again, then Enter on the card: the post.
    page.driver.browser.keyboard.type(:Enter)
    assert page.evaluate_script("document.activeElement === document.querySelector('[data-mind-graph-card]')")
    click_frame_link { page.driver.browser.keyboard.type(:Enter) }
    assert_current_path admin_post_path(a)
  end

  # The notes handoff's decision 12: Enter on the selected node opens the post.
  test "Enter on the canvas opens the selected post, does nothing with nothing selected, and stays a line break in the note's field" do
    a = create_post(title: "Alpha", tags: %w[shared])
    create_post(title: "Beta", tags: %w[shared])
    visit admin_mind_graph_path
    await_graph
    canvas = CANVAS

    # Nothing selected: nothing happens.
    find(canvas).execute_script("this.focus()")
    page.driver.browser.keyboard.type(:Enter)
    await_frames
    assert_current_path admin_mind_graph_path

    click_node(a)
    assert_selector "[data-mind-graph-card] a", text: "Open post"
    # In the note's field Enter is the field's own.
    field = find("[data-mind-graph-card] textarea")
    field.execute_script("this.focus()")
    page.driver.browser.keyboard.type("One", :Enter, "Two")
    await_frames
    assert_equal "One\nTwo", field.value
    assert_current_path admin_mind_graph_path

    find(canvas).execute_script("this.focus()")
    click_frame_link { page.driver.browser.keyboard.type(:Enter) }
    assert_current_path admin_post_path(a)
  end

  # Spec §5.7, as the round of 2026-10-08 left it: the Tab key meets the
  # search first, then a local view's bar, the filter, the zoom buttons, the
  # canvas, the card and, last, the list -- though on screen the search and
  # the list are one column on the right.
  test "the Tab key meets the search first and the list last" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path(post: a.id)
    await_graph
    click_node(a)
    assert_selector "[data-mind-graph-card] a", text: "Open post"

    stops = page.evaluate_script(<<~JS)
      Array.from(document.querySelector(#{GRAPH.to_json}).querySelectorAll("input, button, a[href], canvas[tabindex='0']"))
        .filter((element) => element.checkVisibility() && !element.closest("[hidden]"))
        .map((element) => {
          if (element.id === "mind-graph-search") return "search"
          if (element.closest("[data-mind-graph-focus]")) return "focus bar"
          if (element.closest("[data-mind-graph-legend]")) return "legend"
          if (element.dataset.action?.includes("admin--mind-graph--graph#")) return "zoom"
          if (element.tagName === "CANVAS") return "canvas"
          if (element.closest("[data-mind-graph-card]")) return "card"
          if (element.closest("[data-mind-graph-list]")) return "list"
          return element.outerHTML
        })
    JS

    assert_equal [ "search", "focus bar", "legend", "zoom", "canvas", "card", "list" ], stops.chunk_while { |a, b| a == b }.map(&:first)
    # The toggles, then "Status key…", and every one of them a stop the Tab key
    # makes: none is taken out of the order.
    legend = page.evaluate_script("Array.from(document.querySelectorAll(#{"#{GRAPH} [data-mind-graph-legend] input, #{GRAPH} [data-mind-graph-legend] button".to_json}), (element) => [ element.dataset.name || element.textContent.trim(), element.tabIndex ])")
    assert_equal [ [ "Posts", 0 ], [ "Tags", 0 ], [ "Related", 0 ], [ "Shares a tag", 0 ], [ "Status key…", 0 ] ], legend
  end

  test "a title with markup in it is text in the list and in the search results" do
    nasty = %(<img src=x onerror="window.pwned=1"> & co)
    a = create_post(title: nasty)
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph

    within(LIST) { assert_selector "button span.truncate", exact_text: nasty }
    fill_in "Find a page, post or tag", with: "onerror"
    within("[data-mind-graph-results]") { assert_link nasty }

    assert_no_selector "#{LIST} img, [data-mind-graph-results] img", visible: :all
    assert_nil page.evaluate_script("window.pwned")
  end
end
