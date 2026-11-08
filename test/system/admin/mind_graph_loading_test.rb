require "application_system_test_case"

class Admin::MindGraphLoadingSystemTest < Admin::MindGraphSystemTestCase
  test "every stub of fetch in the graph's browser files remembers the real one, so the teardown can put it back" do
    files = Dir[Rails.root.join("test/system/admin/mind_graph_*_test.rb")].reject { |path| path.end_with?("_modules_test.rb") }
    files << Rails.root.join("test/support/mind_graph_system_test_case.rb").to_s # its stub_graph_data is a stub too
    assert_operator files.size, :>=, 10, "the graph's browser files moved: this test is looking at too little"
    stubs = 0
    forgetful = files.flat_map do |path|
      source = File.read(path)
      # Any assignment but one that puts a real fetch back (`= real`, `= window.realFetch`).
      indexes = source.lines.each_with_index.select { |line, _| line.match?(/window\.fetch = (?!real\b|window\.realFetch)/) }.map { |_, index| index }
      stubs += indexes.size
      # Looked for in the lines above the stub, up to the script's own start (a
      # here-document or a one-line script), not within a fixed distance.
      indexes.reject do |index|
        start = index.downto(0).find { |line| source.lines[line].match?(/execute_script|evaluate_(?:async_)?script/) } || 0
        source.lines[start..index].join.match?(/window\.realFetch (?:\?\?=|=) /)
      end.map { |index| "#{File.basename(path)}: line #{index + 1}" }
    end

    assert_operator stubs, :>, 12
    assert_empty forgetful
  end

  test "the data can't be loaded: a message with Retry, which loads it" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit_screen admin_tags_path
    page.execute_script(<<~JS)
      const original = window.fetch
      window.realFetch ??= original
      window.failGraph = true
      window.fetch = (url, options) => (window.failGraph && String(url).includes("/mind_graph/data") ? Promise.reject(new TypeError("Failed to fetch")) : original(url, options))
    JS

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    assert_selector "#{GRAPH}[data-state='failed']"
    assert_text "The graph could not be loaded."
    assert_no_selector "#{GRAPH}[data-settled]"
    # Retry is the shared button's tertiary look, handed to the script by the view.
    tertiary = JSON.parse(graph["data-button-classes"]).fetch("tertiary").split
    assert_empty tertiary - find_button("Retry")[:class].split, "Retry is not the tertiary button"

    page.execute_script("window.failGraph = false")
    press "Retry"
    await_graph
    assert_no_text "The graph could not be loaded."
    assert_equal "3", graph["data-nodes"]
  end

  test "the server refuses the data: the same message" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit_screen admin_tags_path
    page.execute_script(<<~JS)
      const original = window.fetch
      window.realFetch ??= original
      window.fetch = (url, options) => (String(url).includes("/mind_graph/data") ? Promise.resolve(new Response("", { status: 500 })) : original(url, options))
    JS

    within("nav[aria-label='Modules']") { click_link "Mind graph" }

    assert_selector "#{GRAPH}[data-state='failed']"
    assert_text "The graph could not be loaded."
    assert_button "Retry"
  end

  # A request that gets no answer is given up after
  # 15 seconds and shown like any other failure. The stubbed request never
  # answers but honours its signal, as `fetch` does; the 15 seconds are made 50
  # milliseconds by handing `AbortSignal.timeout` a shorter one, so nothing
  # here waits out the real time.
  test "the data request gets no answer: it times out into the same message, and Retry loads the graph" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit_screen admin_tags_path
    page.execute_script(<<~JS)
      const original = window.fetch
      window.realFetch ??= original
      window.realTimeout ??= AbortSignal.timeout
      const timeout = AbortSignal.timeout.bind(AbortSignal)
      window.hangGraph = true
      window.askedFor = []
      AbortSignal.timeout = (milliseconds) => { window.askedFor.push(milliseconds); return timeout(window.hangGraph ? 50 : milliseconds) }
      window.fetch = (url, options) => {
        if (!window.hangGraph || !String(url).includes("/mind_graph/data")) return original(url, options)
        return new Promise((resolve, reject) => options.signal.addEventListener("abort", () => reject(options.signal.reason)))
      }
    JS

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    assert_selector "#{GRAPH}[data-state='failed']"
    assert_text "The graph could not be loaded."
    assert_equal [ 15_000 ], page.evaluate_script("window.askedFor"), "the request is given fifteen seconds"

    page.execute_script("window.hangGraph = false")
    press "Retry"
    await_graph
    assert_no_text "The graph could not be loaded."
    assert_equal "3", graph["data-nodes"]
  end

  # Six thousand posts are not made for this: the
  # endpoint's answer is replaced by one that says it was cut, and the screen
  # has to say so. Every figure in the sentences is grouped, the isolated
  # count too: it is handed to the message as `%{figure}`, and `count` only
  # chooses the plural form.
  test "over the cap the screen says what it shows and what it leaves out" do
    create_post(title: "A")
    visit_screen admin_tags_path
    stub_graph_data(CAPPED_GRAPH)

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_graph

    assert_text "Showing the 2,000 best-connected of 6,000 posts."
    assert_text "1,214 other posts have no connections yet and aren't shown."
    assert_no_text "Link posts with Related posts"
    assert_equal "2", graph["data-nodes"]
  end

  # At the posts' cap a connected post
  # the cut left out, added from the list, is one more of those shown, and
  # an unconnected one is one fewer of those that aren't: each sentence
  # follows its own figure. And the notice is a live region: a sentence that
  # still says what it said is left as it is (the same element), so a
  # screen reader is not read both again for every post a person adds.
  # The two reads are played (nobody builds a site over the cap); every
  # other request goes to the real fetch, and the list's stub puts it back.
  test "at the cap an added post moves the figure of its own sentence and no other, and a sentence that did not change is not written again" do
    create_post(title: "A")
    create_page(title: "Blog") # a viewer who reads a page has the filter's checkbox
    visit_screen admin_tags_path
    stub_graph_data(CAPPED_GRAPH)
    page.execute_script(<<~JS)
      const real = window.fetch
      window.realFetch ??= real
      window.fetch = (url, options) => {
        if (!String(url).includes("/mind_graph/unlisted")) return real(url, options)
        window.fetch = real
        const row = (id, title, unconnected) => ({ id, title, type: "blog", colour_index: 1, status: "live", changes: null, listed: false, url: "/row", degree: 0, related_count: 0, tag_count: 0, open_notes: 0, unconnected })
        return Promise.resolve(new Response(JSON.stringify({ total: 2, rows: [ row("post-50", "Cut by the cap", false), row("post-51", "No connection", true) ] }), { headers: { "Content-Type": "application/json" } }))
      }
    JS
    lines = -> { all("#{GRAPH} [role=status] p:not([data-mind-graph-announced])").map { |line| [ line.text, line["data-heard"] ] } }
    heard = -> { page.execute_script("document.querySelectorAll(#{"#{GRAPH} [role=status] p".to_json}).forEach((line) => { line.dataset.heard = 'before' })") }
    # What is ADDED to the live region is what a screen reader is read: every paragraph put in, by its words.
    watch = <<~JS
      window.noticeAdded = []
      new MutationObserver((records) => records.forEach((record) => record.addedNodes.forEach((node) => window.noticeAdded.push(node.textContent))))
        .observe(document.querySelector(#{"#{GRAPH} [data-admin--mind-graph--graph-target='notice']".to_json}), { childList: true })
    JS
    added = -> { page.evaluate_script("window.noticeAdded.splice(0)") }

    with_reduced_motion do
      within("nav[aria-label='Modules']") { click_link "Mind graph" }
      await_graph
      assert_equal [ "Showing the 2,000 best-connected of 6,000 posts.", "1,214 other posts have no connections yet and aren't shown." ], lines.call.map(&:first)
      find("#{LIST} label", text: "Not listed on any page").click
      assert_selector "#{LIST} [role=treeitem][data-not-in-view]", count: 2
      page.execute_script(watch)

      heard.call
      find("#{LIST} [role=treeitem][data-node-id='post-50']").click
      assert_selector "#{GRAPH}[data-selected='post-50'][data-nodes='3']"
      assert_equal [ [ "Showing the 2,001 best-connected of 6,000 posts.", nil ], [ "1,214 other posts have no connections yet and aren't shown.", "before" ] ], lines.call,
        "one more is shown; the other sentence is the element it was"
      assert_equal [ "Showing the 2,001 best-connected of 6,000 posts." ], added.call, "and it was never taken out and put back: only the sentence that changed is put into the live region"
      assert_includes find(CANVAS)["aria-label"], "Showing the 2,001 best-connected of 6,000 posts."

      heard.call
      find("#{LIST} [role=treeitem][data-node-id='post-51']").click
      assert_selector "#{GRAPH}[data-selected='post-51'][data-nodes='4']"
      assert_equal [ [ "Showing the 2,001 best-connected of 6,000 posts.", "before" ], [ "1,213 other posts have no connections yet and aren't shown.", nil ] ], lines.call,
        "one fewer isn't shown; the cap's sentence is the element it was"
      assert_equal [ "1,213 other posts have no connections yet and aren't shown." ], added.call
    end
  end

  # "Not listed on any page" is a read of its
  # own and its checkbox is there before the graph is: its rows can come
  # while the graph is still being read, or after that read failed. There is
  # then nothing to add a post to, so a row only says it is not in view, a
  # press does nothing and raises nothing, and once the graph has come the
  # same rows, still there, add their post. The graph's first read is held
  # by the test and then failed; every other request goes to the real fetch.
  test "a row of Not listed on any page pressed while the graph is being read, and after that read failed, does nothing and raises nothing, and adds its post once the graph is there" do
    create_page(title: "Blog")
    alone = create_post(title: "Alone")
    row = "#{LIST} [role=treeitem][data-node-id='#{nid(alone)}'][data-not-in-view]"
    blog = ContentTypes.fetch("blog").label.downcase
    visit_screen admin_tags_path
    page.execute_script(<<~JS)
      const real = window.fetch
      window.realFetch ??= real
      window.fetch = (url, options) => {
        if (!String(url).includes("/mind_graph/data")) return real(url, options)
        window.fetch = real
        return new Promise((resolve, reject) => { window.failGraphRead = () => reject(new TypeError("Failed to fetch")) })
      }
    JS

    with_reduced_motion do
      within("nav[aria-label='Modules']") { click_link "Mind graph" }
      assert_selector "#{GRAPH}[data-state='loading']"
      await_js("typeof window.failGraphRead === 'function'")
      find("#{LIST} label", text: "Not listed on any page").click
      assert_selector "#{row}[aria-disabled='true'][aria-label='Alone, #{blog} post, not in view.']", text: /Alone\s*not in view/

      find(row).click
      await_frames
      assert_selector "#{GRAPH}[data-state='loading']:not([data-nodes])"
      assert_selector "#{row}[aria-disabled='true']", count: 1
      assert_no_selector "[data-mind-graph-card]", visible: :visible, wait: 0

      page.execute_script("window.failGraphRead()")
      assert_selector "#{GRAPH}[data-state='failed']"
      find(row).click
      await_frames
      assert_selector "#{row}[aria-disabled='true']", count: 1
      assert_selector "#{LIST} input[data-mind-graph-unlisted]:checked", visible: :all

      # The graph comes: what the person asked for is still there, and now it adds.
      press "Retry"
      await_graph
      assert_selector "#{LIST} input[data-mind-graph-unlisted]:checked", visible: :all
      assert_selector "#{row}:not([aria-disabled])"
      within(LIST) { assert_row "Alone, #{blog} post, not in view. Activate to add it to the graph." }
      find(row).click
      assert_selector "#{GRAPH}[data-selected='#{nid(alone)}'][data-nodes='3']"
      assert_selector "#{LIST} [role=treeitem][data-node-id='#{nid(alone)}']:not([data-not-in-view])[aria-selected='true']"
    end
  end

  # A local view is cut differently (`PostGraph::Local#cut`: the nearest posts
  # first, then the better connected), so it has a sentence of its own: "best-
  # connected" would be untrue of it.
  test "over the cap a local view says it shows the nearest posts, not the best-connected" do
    create_post(title: "A")
    visit_screen admin_tags_path
    stub_graph_data(CAPPED_LOCAL_GRAPH)

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_graph

    assert_text "Showing the 2,000 nearest of 2,695 posts around this one."
    assert_no_text "best-connected"
    assert_equal "2", graph["data-nodes"]
  end

  # Home is held at the centre in the whole
  # graph only. In a local view it is the FOCUS that rests at the centre --
  # a person who asks for the graph around a page expects that page in the
  # middle -- and Home, when it is drawn, is a page like any other. Neither
  # is a pin.
  test "in a local view the focus rests at the centre and Home does not" do
    home = root_page
    journal = create_page(title: "Journal")
    create_page(title: "Archive", parent: journal)

    visit admin_mind_graph_path(page: journal.id)
    await_graph

    assert_equal "3", graph["data-nodes"]
    at = graph_position(journal)
    assert_in_delta 0, at["x"], 0.5, "the focus is not at the centre"
    assert_in_delta 0, at["y"], 0.5
    assert_operator Math.hypot(graph_position(home)["x"], graph_position(home)["y"]), :>, 20, "Home is held at the centre of a view that is not its own"
    assert_equal "0", graph["data-pinned"]
    assert_no_button "Release 1 pinned"
  end

  # The numbers in those sentences are written the way the UI's language
  # writes them -- the `@locale` the server's messages name -- and not the way
  # the browser's own locale would. There is no German UI yet, so the test says
  # the messages are German between a failed load and its Retry.
  test "the cap's numbers are formatted for the language of the messages, not the browser's" do
    create_post(title: "A")
    visit_screen admin_tags_path
    page.execute_script("window.failGraph = true")
    stub_graph_data(CAPPED_GRAPH)

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    assert_selector "#{GRAPH}[data-state='failed']"
    page.execute_script(<<~JS)
      const element = document.querySelector(#{GRAPH.to_json})
      element.setAttribute("data-messages", JSON.stringify({ ...JSON.parse(element.getAttribute("data-messages")), "@locale": "de" }))
      window.failGraph = false
    JS
    press "Retry"
    await_graph

    assert_text "Showing the 2.000 best-connected of 6.000 posts."
    assert_text "1.214 other posts have no connections yet and aren't shown."
  end

  # The choice is not remembered after a reload. The threshold is lowered for
  # the server this test's browser talks to: nobody builds three thousand
  # lines, and no request is played.
  test "a site with too many lines opens around Home and says why, Show everything draws the whole graph in the same page, and neither a reload nor Back remembers it" do
    home = root_page
    first = create_page(title: "Page 0")
    2.times { |index| create_page(title: "Page #{index + 1}") }
    create_page(title: "Deep", parent: first)
    whole = PostGraph::Global.method(:call)
    bar = "#{GRAPH} [data-mind-graph-opened]"
    around_home = lambda do
      assert_selector "#{bar}:not([hidden])", text: "This site has 4 connections, so the graph opens around Home."
      assert_equal %w[4 4 3], [ graph["data-opened-lines"], graph["data-nodes"], graph["data-edges"] ], "Home and its three children: the grandchild is not in this view"
      assert_selector "#{CANVAS}[aria-label='Mind graph around Home, depth 1: 4 pages. Showing the area around Home. The site has 5 pages.']"
    end

    with_singleton_override(PostGraph::Global, :call, ->(**options) { whole.call(**options, open_above: 3) }) do
      with_reduced_motion do
        visit admin_mind_graph_path
        await_graph

        around_home.call
        assert_current_path admin_mind_graph_path, ignore_query: false
        assert_selector "#{bar} button[type=button][aria-label='Show everything: all 4 connections'][aria-describedby='mind-graph-opened-line']", exact_text: "Show everything"
        everything = find("#{bar} button[aria-label='Show everything: all 4 connections']")
        assert_equal Admin::Ui::ButtonComponent.classes(:tertiary, size: :small).split.sort, everything[:class].split.sort, "Show everything is not the shared small tertiary button"
        assert_no_selector "[data-mind-graph-focus]"
        assert_selector "#{GRAPH} [role=status] p.sr-only[data-mind-graph-announced]", text: "Showing the area around Home. The site has 5 pages.", visible: :all
        assert_nil screen_position("page-#{Page.find_by!(parent: first).id}")
        at = graph_position(home)
        assert_in_delta 0, at["x"], 0.5, "Home, the focus of the view, rests at the centre"
        assert_in_delta 0, at["y"], 0.5
        click_node(nid(first))
        assert_selector "[data-mind-graph-card]", text: /1 child page/i

        within(bar) { press "Show everything" }
        assert_selector "#{GRAPH}[data-nodes='5'][data-edges='4']", wait: 10
        await_graph
        assert_no_selector bar
        assert_nil graph["data-opened-lines"]
        assert_equal "", graph["data-selected"], "the selection was of the view that went"
        assert_no_selector "[data-mind-graph-card]", visible: :visible
        assert_selector "#{CANVAS}[aria-label='Mind graph: 5 pages, 4 connections. Showing everything.']"
        # The press is answered for a screen reader too: the whole graph's summary, in the notice's live region.
        assert_selector "#{GRAPH} [role=status] p.sr-only[data-mind-graph-announced]", text: /\AMind graph: 5 pages, 4 connections\. Showing everything\.\z/, visible: :all
        within(LIST) { assert_equal [ "PAGES · 5" ], list_headings }
        assert screen_position("page-#{Page.find_by!(parent: first).id}")
        assert_current_path admin_mind_graph_path, ignore_query: false
        assert_equal "/cs-studio/mind_graph/data", graph["data-url"], "nothing of the page says everything: the choice is in no address"

        # Not remembered after a reload.
        visit admin_mind_graph_path
        await_graph
        around_home.call

        # Nor by Back: the page Turbo restores is the page as it is served.
        within(bar) { press "Show everything" }
        assert_selector "#{GRAPH}[data-nodes='5']", wait: 10
        await_graph
        click_frame_link { within("nav[aria-label='Modules']") { click_link "Tags" } }
        assert_selector "h1", text: "Tags"
        page.go_back
        await_graph
        around_home.call
        assert_selector "#{bar} button[aria-label='Show everything: all 4 connections']"

        # Left while it says "around Home", and the data then fails: the page
        # Turbo restores says nothing of a view that is not drawn (the
        # controller's `reset` took the figure and the bar back). The stub
        # fails the one request and puts the real fetch back.
        click_frame_link { within("nav[aria-label='Modules']") { click_link "Tags" } }
        assert_selector "h1", text: "Tags"
        page.execute_script(<<~JS)
          const real = window.fetch
      window.realFetch ??= real
          window.fetch = (url, options) => {
            if (!String(url).includes("/mind_graph/data")) return real(url, options)
            window.fetch = real
            return Promise.reject(new TypeError("Failed to fetch"))
          }
        JS
        page.go_back
        assert_selector "#{GRAPH}[data-state='failed']", wait: 10
        assert_nil graph["data-opened-lines"]
        assert_no_selector bar
        assert_selector "#{bar}[hidden] [data-mind-graph-opened-line]:empty", visible: :all
        assert_selector "#{bar} button:not([aria-label])", visible: :all
        press "Retry"
        await_graph
        around_home.call
      end
    end
  end
end
