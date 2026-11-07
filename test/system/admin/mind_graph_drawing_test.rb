require "application_system_test_case"

class Admin::MindGraphDrawingSystemTest < Admin::MindGraphSystemTestCase
  test "the graph loads, settles, and the first view fits every node inside the canvas" do
    posts = 6.times.map { |i| create_post(title: "Post #{i}", tags: [ "shared" ]) }
    PostRelation.create!(post: posts[0], related_post: posts[1])

    visit admin_mind_graph_path
    await_graph

    assert_equal "7", graph["data-nodes"], "six posts and the tag they share"
    assert_equal "7", graph["data-edges"], "one related and six tag edges"
    assert_selector "#{CANVAS}[aria-label='Mind graph: 6 posts and 1 tag, 7 connections. Showing everything.']"
    assert_equal [ "Posts 6", "Tags 1", "Related 1", "Shares a tag 6" ], legend_counts, "no page is read here, so no toggle of pages"
    box = canvas_box
    (posts + [ Tag.find_by!(name: "shared") ]).map { |record| nid(record) }.each do |id|
      point = screen_position(id)
      assert point, "no position for #{id}"
      assert point["x"].between?(box[0], box[2]) && point["y"].between?(box[1], box[3]), "#{id} is outside the canvas: #{point} in #{box}"
    end
    assert_no_text "Loading the graph…"
  end

  # The screen fills the window: the box is (almost)
  # the content column wide -- main's width less its padding -- and ends
  # exactly where the window does less that padding, so the page itself does
  # not scroll. Inside it the canvas is on the left and the search and the
  # list are a 300px column on its right, the search on top.
  test "the screen fills the window: the page does not scroll, and the list stands beside the canvas" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph

    sizes = layout_boxes

    assert_operator sizes["page"], :<=, sizes["viewport"], "the page scrolls: #{sizes}"
    assert_operator sizes["box"]["width"], :>=, sizes["main"] - 60
    assert_operator sizes["box"]["width"], :<=, sizes["main"]
    assert_in_delta sizes["viewport"] - 24, sizes["box"]["bottom"], 2, "the box does not reach the bottom of the window: #{sizes}"
    assert_operator sizes["canvas"]["height"], :>, 600
    assert_in_delta 300, sizes["list"]["width"], 2
    assert_in_delta sizes["canvas"]["right"], sizes["list"]["left"], 2, "the list is not beside the canvas: #{sizes}"
    assert_in_delta sizes["list"]["left"], sizes["search"]["left"], 16
    assert_operator sizes["search"]["bottom"], :<=, sizes["list"]["top"] + 1, "the search field is not above the list"
    assert_in_delta sizes["box"]["bottom"], sizes["list"]["bottom"], 2, "the list does not reach the bottom of the box"
    assert_in_delta sizes["box"]["bottom"], sizes["canvas"]["bottom"], 2
  end

  # Below about 1,100 px the list has no room beside the canvas: it stands
  # under it, with the search field between them, and the page may scroll.
  test "in a window narrower than 1,100 pixels the search and the list stand under the canvas" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph
    original = page.current_window.size

    begin
      page.current_window.resize_to(1000, 900)
      await_js("document.querySelector(#{CANVAS.to_json}).getBoundingClientRect().width > 800")
      sizes = layout_boxes

      assert_in_delta sizes["box"]["width"], sizes["canvas"]["width"], 4, "the canvas is not as wide as the box: #{sizes}"
      assert_in_delta sizes["box"]["width"], sizes["list"]["width"], 4
      assert_operator sizes["search"]["top"], :>=, sizes["canvas"]["bottom"], "the search field is not under the canvas: #{sizes}"
      assert_operator sizes["list"]["top"], :>=, sizes["search"]["bottom"] - 1, "the list is not under the search field: #{sizes}"
      assert_operator sizes["canvas"]["height"], :>=, 480
    ensure
      page.current_window.resize_to(*original)
    end
  end

  test "the canvas is sharp: its bitmap is the box times the device pixel ratio" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph

    sizes = page.evaluate_script("(() => { const c = document.querySelector(#{CANVAS.to_json}); const r = c.getBoundingClientRect(); return [c.width, Math.round(r.width * window.devicePixelRatio), c.height, Math.round(r.height * window.devicePixelRatio)] })()")

    assert_equal sizes[1], sizes[0]
    assert_equal sizes[3], sizes[2]
    assert_operator sizes[0], :>, 0
  end

  # One look read from the canvas's own pixels, so that "it draws at all" and
  # "a draft is dashed" are seen on the real canvas, not only asked of a
  # recording one (every look's detail is in the module tests): a live post is
  # filled to its edge; a draft is empty inside, and its outline is there at
  # some points round it and not at others.
  #
  # The ring is read 6.25px from the centre: the middle of the outline's
  # band, which is INSIDE the mark's edge (5.5 to 7, on a surface disk of
  # radius 7), so every sample has the surface under it. A sample in a gap is
  # the surface's own colour, one on a dash is mixed with the outline's. And
  # nothing is drawn a pixel beyond the mark's own radius: a draft is as
  # large as a live post's fill, not half a stroke larger.
  test "a live post is filled and a draft is an empty, dashed outline" do
    live = create_post(title: "Live one")
    draft = create_post(title: "Draft one")
    draft.update_column(:published_at, nil)
    PostRelation.create!(post: live, related_post: draft)
    visit admin_mind_graph_path
    await_graph

    surface = pixel_at(*canvas_box.first(2).map { |edge| edge + 3 })
    live_centre, live_inside = pixels_of(live)
    draft_centre, draft_inside = pixels_of(draft)
    round = ring_pixels(draft, radius: 6.25, samples: 96)
    beyond = ring_pixels(draft, radius: 8, samples: 24, quadrant: :left)
    far = ->(pixel) { pixel.first(3).zip(draft_centre.first(3)).map { |a, b| (a - b).abs }.max }

    assert_operator surface[3], :<, 10, "the canvas's corner is not empty: #{surface}"
    assert_equal 255, live_centre[3], "nothing is drawn where the live post is"
    assert_equal live_centre, live_inside, "a live post is filled out to its edge"
    assert_equal 255, draft_centre[3], "a draft has no surface inside"
    assert_not_equal live_centre, draft_centre, "a draft is empty inside: no core in its type's hue"
    assert_equal draft_centre, draft_inside, "a draft is empty inside, out to its outline"
    assert_operator round.count { |pixel| far.call(pixel) <= 8 }, :>, 12, "the outline has no gaps: it is not dashed"
    assert_operator round.count { |pixel| far.call(pixel) > 24 }, :>, 12, "no outline is drawn round the draft"
    assert_operator beyond.count { |pixel| pixel[3] > 40 }, :<, 8, "an outline is drawn beyond the draft's radius: it is not inside the mark's edge (a line to a neighbour may cross a few of the samples)"
  end

  # Pages, the post type a page lists and All posts are on
  # the canvas; Home rests at the centre of the layout and is no pin; dragged,
  # it is pinned where it is dropped, and released it goes back.
  test "pages and what they list are drawn, and Home rests at the centre without being pinned" do
    home = root_page
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    ContentBlock.create!(owner: home, block_type: :post_list, position: 0, settings: {})
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))

    visit admin_mind_graph_path
    await_graph

    assert_equal [ "6", "4" ], [ graph["data-nodes"], graph["data-edges"] ], "two pages, two posts, the type and All posts; a tree line, two lists lines and one related"
    [ home, blog, a, "type-blog", "all-posts" ].each { |node| assert screen_position(nid(node)), "#{nid(node)} is not drawn" }
    at = graph_position(home)
    assert_in_delta 0, at["x"], 0.5
    assert_in_delta 0, at["y"], 0.5
    assert_equal "0", graph["data-pinned"]
    assert_no_button "Release 1 pinned"
    labelled = graph["data-labelled"].split(",")
    assert_equal nid(home), labelled.first, "Home's label is placed first"
    assert_empty [ nid(blog), "type-blog", "all-posts" ] - labelled, "a top-level page, a post type and All posts are named: #{labelled}"
    # The marks on the real canvas. Home is a card 18 wide and 13 high, not a
    # dot. Ink 7.5px right of its centre and in its corner (7.5 right, 5
    # down: 9px from the centre), where a dot as high as it has nothing; and
    # nothing 8px above and below its centre, where a dot as wide as it is
    # filled (the lower of the two readings, since a line may cross one). No
    # one pixel tells a card's corner from a dot of radius 9: the two differ
    # there by less than the pixel the mark may be off the grid, so it is the
    # height that says "not a dot as wide".
    home_at = screen_position(home)
    centre = pixel_at(home_at["x"], home_at["y"])
    assert_equal 255, centre[3]
    assert_equal centre, pixel_at(home_at["x"] + 7.5, home_at["y"]), "Home is not 18 wide: nothing 7.5px right of its centre"
    assert_operator pixel_at(home_at["x"] + 7.5, home_at["y"] + 5)[3], :>, 200, "Home's card has no corner"
    assert_operator [ pixel_at(home_at["x"], home_at["y"] + 8)[3], pixel_at(home_at["x"], home_at["y"] - 8)[3] ].min, :<, 100, "Home is as high as it is wide: a dot, not a card"
    hub = screen_position("type-blog")
    assert_not_equal pixel_at(hub["x"], hub["y"]), pixel_at(hub["x"] + 3.75, hub["y"]), "the hub has no ring inside it: it is one more post"

    drag_node(nid(home), by: [ 90, 60 ])
    assert_equal "1", graph["data-pinned"]
    await_graph
    assert_operator Math.hypot(graph_position(home)["x"], graph_position(home)["y"]), :>, 20, "a dragged Home is held where it was dropped"

    press "Release 1 pinned"
    await_graph
    assert_in_delta 0, graph_position(home)["x"], 0.5, "a released Home did not go back to the centre"
    assert_in_delta 0, graph_position(home)["y"], 0.5
    assert_equal "0", graph["data-pinned"]
  end

  # Hubs are labelled first and the rest arrive
  # with zoom. The fitted view of 66 nodes has room for every label, so the
  # test first zooms OUT, to where only the best-connected are named (every
  # node still on the canvas), and then back in. (Zooming in from the fitted
  # view names FEWER nodes, not more: most of them leave the canvas, and a
  # node outside it has no label.)
  test "the zoom buttons zoom, hubs are labelled first and more labels arrive with zoom, and Fit all brings everything back" do
    posts = 60.times.map { |i| create_post(title: "Post #{i}", tags: [ "t#{i % 6}" ]) }
    posts.each_cons(2) { |a, b| PostRelation.create!(post: a, related_post: b) }
    tag_ids = Tag.where(name: 6.times.map { |i| "t#{i}" }).map { |tag| "tag-#{tag.id}" }
    visit admin_mind_graph_path
    await_graph
    zoom = "Number(document.querySelector(#{GRAPH.to_json}).dataset.zoom)"
    labelled = -> { graph["data-labelled"].split(",") }

    fitted = graph["data-zoom"].to_f
    # The figure between the two zoom buttons is the zoom, as a percentage.
    assert_selector "[data-mind-graph-zoom]", exact_text: "#{(fitted * 100).round}%"
    4.times { press "Zoom out" }
    await_js("Math.abs(#{zoom} - #{fitted / (1.4**4)}) < 0.002")
    await_frames
    far = labelled.call
    assert_operator far.size, :<, 20, "zoomed far out, only the hubs are named: #{far}"
    assert_operator far.size, :>, 0
    # A tag here has ten edges, a post three: the hubs are the tags.
    assert_operator (far & tag_ids).size, :>=, [ far.size, tag_ids.size ].min - 1, "the labels did not go to the best-connected first: #{far} (tags: #{tag_ids})"

    2.times { press "Zoom in" }
    await_js("Math.abs(#{zoom} - #{fitted / (1.4**2)}) < 0.002")
    await_frames
    nearer = labelled.call
    assert_operator nearer.size, :>, far.size, "no label arrived with the zoom"

    press "Zoom in"
    press "Fit all"
    await_js("Math.abs(#{zoom} - #{fitted}) < 0.002")
    await_frames
    assert_operator labelled.call.size, :>=, nearer.size
  end

  test "the wheel zooms and a drag on empty space pans" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph
    before = graph["data-zoom"].to_f
    first_id = nid(Post.order(:id).first)
    corner = canvas_box.first(2).map { |edge| edge + 12 }

    # Ferrum's mouse has no wheel (its `scroll_to` is `window.scrollTo`), so the
    # wheel is sent the way its clicks are: a native input event through CDP.
    mouse = page.driver.browser.mouse
    mouse.move(x: corner[0], y: corner[1])
    page.driver.browser.page.command("Input.dispatchMouseEvent", type: "mouseWheel", x: corner[0], y: corner[1], deltaX: 0, deltaY: 240)
    await_js("Number(document.querySelector(#{GRAPH.to_json}).dataset.zoom) < #{before}")

    moved_from = screen_position(first_id)
    mouse.move(x: corner[0], y: corner[1])
    mouse.down
    mouse.move(x: corner[0] + 60, y: corner[1] + 40)
    mouse.up
    await_js("(() => { const p = document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{first_id.to_json}); return Math.abs(p.x - #{moved_from["x"] + 60}) < 2 && Math.abs(p.y - #{moved_from["y"] + 40}) < 2 })()")
  end

  # With the canvas focused, + and - zoom around
  # its middle and the arrow keys pan.
  test "with the canvas focused, + and - zoom and the arrow keys pan" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph
    first_id = nid(Post.order(:id).first)
    zoom = -> { graph["data-zoom"].to_f }
    fitted = zoom.call

    canvas = find(CANVAS)
    canvas.send_keys("-")
    await_js("Number(document.querySelector(#{GRAPH.to_json}).dataset.zoom) < #{fitted}")
    smaller = zoom.call
    canvas.send_keys("+")
    await_js("Number(document.querySelector(#{GRAPH.to_json}).dataset.zoom) > #{smaller}")

    from = screen_position(first_id)
    canvas.send_keys(:right)
    await_js("(() => { const p = document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{first_id.to_json}); return Math.abs(p.x - #{from["x"] - 60}) < 1 && Math.abs(p.y - #{from["y"]}) < 1 })()")
    canvas.send_keys(:down)
    await_js("(() => { const p = document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{first_id.to_json}); return Math.abs(p.x - #{from["x"] - 60}) < 1 && Math.abs(p.y - #{from["y"] - 60}) < 1 })()")
  end

  # One number is three nodes (the three tables count on their own): the post, the tag
  # and the page of id 12 are each drawn, each selected by its own id, with
  # its own neighbours. A page's card and a pill's are their name and Pin
  # until each has its own. The pill is as wide as its
  # words, is pressed on its box and not on a circle as wide as it, and has
  # no label beside it, hovered or not.
  test "a post, a tag and a page of one database id are three nodes, and a page, a type and a pill are drawn and pressed" do
    create_post(title: "A")
    visit_screen admin_tags_path
    stub_graph_data(SHARED_ID_GRAPH)
    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_graph

    assert_equal [ "6", "6" ], [ graph["data-nodes"], graph["data-edges"] ], "two posts, the tag, the page, the type and the pill; every line the data holds"
    # The legend has no toggle for pages here (the viewer reads none, and the
    # data is a stub's): a kind is hidden by a toggle switched off, never by
    # a toggle that is not there.
    assert_no_selector "#{GRAPH} label[data-legend-toggle=page], #{GRAPH} label[data-legend-toggle=type]"
    # A selected label is semibold, and its box is measured in that font: the
    # hit target and the hover's backing are as wide as the words drawn.
    click_node("post-12")
    assert_equal "post-12", graph["data-selected"]
    assert_equal %w[post-13 tag-12], graph["data-neighbours"].split(",").sort
    await_frames
    widths = page.evaluate_script(<<~JS)
      (() => {
        const canvas = document.querySelector(#{CANVAS.to_json})
        const box = canvas.parentElement.closest(#{GRAPH.to_json}).mindGraph.labelBox("post-12")
        const context = document.createElement("canvas").getContext("2d")
        const measured = (weight) => { context.font = `${weight}12px ${getComputedStyle(canvas).fontFamily}`; return context.measureText("Twelve").width }
        return { box: box.right - box.left - 4, regular: measured(""), semibold: measured("600 ") }
      })()
    JS
    assert_operator widths["semibold"], :>, widths["regular"] + 0.5, "the two fonts are as wide as each other here: the test shows nothing"
    assert_in_delta widths["semibold"], widths["box"], 0.01, "the selected label's box is not as wide as the semibold words drawn"
    click_node("tag-12")
    assert_equal "tag-12", graph["data-selected"]
    assert_equal %w[page-12 post-12 post-13], graph["data-neighbours"].split(",").sort
    click_node("page-12")
    assert_equal "page-12", graph["data-selected"]
    assert_equal %w[tag-12 type-blog], graph["data-neighbours"].split(",").sort
    within("[data-mind-graph-card]") do
      assert_selector "h2", exact_text: "Page twelve"
      assert_button "Pin"
      assert_no_link "Open post"
      # A page and a post of ONE database id: the page's card leads to the
      # page, and its notes are the page's, not post 12's.
      assert_link "Open page", href: %r{/pages/12\z}
      assert_link "Focus", href: /mind_graph\?page=12\z/
      assert_selector "[data-mind-graph-card-notes][data-notes-type=page][data-notes-id='12']"
    end
    assert_raises(ArgumentError) { nid(12) }

    # The pill: "+1,980 more" in the messages' language, wider than the least.
    escape_on_canvas
    pill = screen_position("more-type-blog")
    box = page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.markBox('more-type-blog')")
    width = box["right"] - box["left"]
    assert_equal [ 16, pill["x"] ], [ box["bottom"] - box["top"], (box["left"] + box["right"]) / 2 ]
    assert_nil page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.markBox('type-blog')"), "a hub is a circle"
    assert_operator width, :>, 60, "the pill did not grow with its words"
    mouse = page.driver.browser.mouse
    mouse.click(x: pill["x"], y: pill["y"] - 20)
    assert_equal "", graph["data-selected"], "20px above the pill is not on it, though it is within a circle as wide as the pill"
    mouse.move(x: pill["x"] + (width / 2) - 2, y: pill["y"] + 5)
    await_js("document.querySelector(#{GRAPH.to_json}).dataset.hovered === 'more-type-blog'")
    await_frames
    assert_not_includes graph["data-labelled"].split(","), "more-type-blog", "a pill has no label beside it"
    # Pressed near its end, the pill is not selected: it
    # opens the list with its posts, asked for by its page's NUMBER and its
    # target (the pill carries the page as a node's id, "page-12"). The read
    # is played here, since page 12 is the stub's; every other request goes
    # to the real fetch.
    page.execute_script(<<~JS)
      const real = window.fetch
      window.realFetch ??= real
      window.listedAsked = []
      window.fetch = (url, options) => {
        if (!String(url).includes("/mind_graph/listed")) return real(url, options)
        window.listedAsked.push(String(url))
        const rows = [ { id: "post-99", title: "Ninety-nine", type: "blog", colour_index: 1, status: "live", degree: 0, related_count: 0, tag_count: 0, open_notes: 0, url: "/ninety-nine", via: "type-blog" } ]
        return Promise.resolve(new Response(JSON.stringify({ total: 1980, rows, posts_url: "/cs-studio/posts?type=blog" }), { headers: { "Content-Type": "application/json" } }))
      }
    JS
    mouse.click(x: pill["x"] + (width / 2) - 2, y: pill["y"] + 5)
    within(LIST) do
      assert_equal [ "MORE FROM BLOG POST · 1,980" ], all("h2").map { |heading| heading.text.upcase }, "named by what the pill hangs off, with the read's whole total, grouped, though it answered one row"
      assert_row "Ninety-nine, #{ContentTypes.fetch("blog").label.downcase} post, not in view. Activate to add it to the graph."
    end
    assert_equal [ "/cs-studio/mind_graph/listed?page=12&target=type-blog" ], page.evaluate_script("window.listedAsked")
    assert_equal "", graph["data-selected"], "more is not selected"
    assert_no_selector "[data-mind-graph-card]", visible: :visible
  end

  # A notice line is a chip around its own words, not a bar as wide as the
  # longest line beside it, and an action of the card is a button around its
  # own word, so a click beside it is not a click on it. The line is `w-fit`,
  # a class only the mind graph's scripts use: this is the built stylesheet's
  # own answer to whether Tailwind read them (`test/lib/tailwind_sources_test.rb`
  # is the guard on the source). The capped answer, because it gives two lines
  # of different lengths.
  test "a notice line and an action of the card are as wide as their text, not as their container" do
    create_post(title: "A")
    visit_screen admin_tags_path
    stub_graph_data(CAPPED_GRAPH)
    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_graph
    click_node("post-1")
    assert_selector "[data-mind-graph-card] a", text: "Open post"

    widths = page.evaluate_script(<<~JS)
      (() => {
        const graph = document.querySelector(#{GRAPH.to_json})
        const width = (element) => element.getBoundingClientRect().width
        const text = (element) => { const range = document.createRange(); range.selectNodeContents(element); return width(range) }
        const line = Array.from(graph.querySelectorAll("[data-admin--mind-graph--graph-target='notice'] p")).at(0)
        const link = graph.querySelector("[data-mind-graph-card] a")
        return { line: width(line), lineText: text(line), notice: width(line.parentElement), link: width(link), linkText: text(link), card: width(link.closest("[data-mind-graph-card]")) }
      })()
    JS

    assert_in_delta widths["lineText"], widths["line"], 10, "the shorter notice line is not as wide as its text (plus its padding): #{widths}"
    assert_operator widths["line"], :<, widths["notice"] - 20, "the shorter notice line is as wide as the longer one: #{widths}"
    assert_in_delta widths["linkText"], widths["link"], 20, "the card's action is wider than its text and its padding: #{widths}"
    assert_operator widths["link"], :<, widths["card"] / 2, "the card's action stretches across the card: #{widths}"
  end

  # Review focus 4.
  test "a box that changes size is redrawn at the new size and still holds every node" do
    posts = 5.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph
    original = page.current_window.size
    width_before = page.evaluate_script("document.querySelector(#{CANVAS.to_json}).width")

    begin
      page.current_window.resize_to(900, 620)
      await_js("(() => { const c = document.querySelector(#{CANVAS.to_json}); const r = c.getBoundingClientRect(); return c.width !== #{width_before} && c.width === Math.round(r.width * window.devicePixelRatio) && c.height === Math.round(r.height * window.devicePixelRatio) })()")
      press "Fit all"
      box = canvas_box
      posts.each do |post|
        point = screen_position(post)
        assert point["x"].between?(box[0], box[2]) && point["y"].between?(box[1], box[3]), "#{post.id} is outside the resized canvas: #{point} in #{box}"
      end
      assert_equal 255, pixels_of(posts.first).first[3], "nothing is drawn at the new size"
    ensure
      page.current_window.resize_to(*original)
    end
  end

  test "the theme's colours are read from the page, and the graph is redrawn when the theme changes" do
    posts = 2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_mind_graph_path
    await_graph

    before = pixels_of(posts.first).first
    draws = page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.draws()")
    theme = page.evaluate_script("document.documentElement.getAttribute('data-theme')")
    # A swatch is a canvas too: it holds colours, not tokens, so the
    # legend's and the Status key's are drawn again with the theme (the key
    # is a closed dialog outside the graph's element, with its own painter).
    swatches = "Array.from(document.querySelectorAll('[data-mind-graph-legend] canvas[data-swatch], #mind-graph-status-key canvas[data-swatch]'), (canvas) => canvas.toDataURL())"
    await_js("#{swatches}.length === 11 && document.querySelector('#mind-graph-status-key canvas').getContext('2d').getImageData(0, 0, 18, 18).data.some((value) => value > 0)")
    painted = page.evaluate_script(swatches)
    begin
      page.execute_script("document.documentElement.setAttribute('data-theme', #{(theme == "dark" ? "light" : "dark").to_json})")
      await_js("document.querySelector(#{GRAPH.to_json}).mindGraph.draws() > #{draws}")

      assert_not_equal before, pixels_of(posts.first).first, "the post's dot kept the other theme's colour"
      await_js("(() => { const before = #{painted.to_json}; return #{swatches}.every((drawing, index) => drawing !== before[index]) })()")
    ensure
      page.execute_script("document.documentElement.setAttribute('data-theme', #{theme.to_json})")
    end
  end

  # Reduced motion: the page tells the worker, and the layout is
  # shown ONCE, at rest -- one `tick`, then `settled`. A dragged node moves
  # alone, its neighbours stay put until the drop, and the drop shows the
  # result in one step.
  test "with reduced motion the layout arrives without intermediate frames, and a dragged node moves alone until the drop" do
    a, b, c = %w[A B C].map { |title| create_post(title: title) }
    PostRelation.create!(post: a, related_post: b)
    PostRelation.create!(post: b, related_post: c)
    visit_screen admin_tags_path
    record_worker_answers

    with_reduced_motion do
      within("nav[aria-label='Modules']") { click_link "Mind graph" }
      await_graph
      assert_equal %w[tick settled], worker_answers, "the layout was shown in more than one step"

      neighbours = [ screen_position(b), screen_position(c) ]
      dropped = drag_node(a, by: [ 90, 70 ], release: false)
      await_frames
      assert_equal neighbours, [ screen_position(b), screen_position(c) ], "a neighbour moved while the node was still held"
      drags = worker_answers.size - 2
      assert_operator drags, :>=, 1
      assert_equal [ "tick" ], worker_answers.last(drags).uniq, "a drag was answered by something other than the node's own move"

      page.driver.browser.mouse.up
      await_graph
      assert_equal %w[tick settled], worker_answers.last(2)
      assert_equal drags + 4, worker_answers.size, "the drop was shown in more than one step: #{worker_answers}"
      assert_not_equal neighbours, [ screen_position(b), screen_position(c) ], "the drop did not lay the neighbours out again"
      at = screen_position(a)
      assert_in_delta dropped["x"], at["x"], 2
      assert_in_delta dropped["y"], at["y"], 2
    end
  end

  # Without reduced motion a small graph unfolds: the page is sent a frame for
  # each tick of the simulation, and draws them.
  test "a small graph unfolds frame by frame" do
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit_screen admin_tags_path
    record_worker_answers

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_graph

    answers = worker_answers
    assert_equal "settled", answers.last
    assert_operator answers.count("tick"), :>, 200, "the layout jumped to its end"
    assert_equal 1, answers.count("settled")
    # (How many depends on how many frames the browser got to draw in those
    # seconds, so only: clearly more than the one or two of a layout that
    # arrives finished.)
    assert_operator page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.draws()"), :>, 10, "the frames in between were not drawn"
  end

  # A `tick` the worker posted BEFORE it
  # took an `add` is two numbers short of the page's nodes. Whether one is in
  # flight is a matter of milliseconds, so the test plays it: the worker's
  # wrapper hands the page the last positions it answered (which know
  # nothing of the new post) in the same task as the `add`, and asks at once
  # where the added post is. It is where the page put it; taken as it came,
  # the short answer left it nowhere (NaN) until the worker's next.
  test "a tick the worker posted before it took an added post leaves that post where the page put it" do
    create_page(title: "Blog")
    alone = create_post(title: "Alone")
    visit_screen admin_tags_path
    page.execute_script(<<~JS)
      window.RealWorker = window.Worker
      window.Worker = class extends window.RealWorker {
        constructor(...args) {
          super(...args)
          this.addEventListener("message", ({ data }) => { if (data.type === "tick") this.lastTick = Float32Array.from(data.positions) })
        }
        postMessage(message, ...rest) {
          super.postMessage(message, ...rest)
          if (message.type !== "add" || !this.lastTick) return
          this.dispatchEvent(new MessageEvent("message", { data: { type: "tick", positions: this.lastTick } }))
          const at = document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(message.node.id)
          window.afterShortTick = { known: this.lastTick.length / 2, placed: Boolean(at) && Number.isFinite(at.x) && Number.isFinite(at.y) }
        }
      }
    JS
    begin
      with_reduced_motion do
        within("nav[aria-label='Modules']") { click_link "Mind graph" }
        await_graph
        find("#{LIST} label", text: "Not listed on any page").click
        find("#{LIST} button[data-node-id='#{nid(alone)}'][data-not-in-view]").click
        assert_selector "#{GRAPH}[data-selected='#{nid(alone)}'][data-nodes='3']"
        assert_equal({ "known" => 2, "placed" => true }, page.evaluate_script("window.afterShortTick"), "the worker's answer knew two nodes, the page holds three: the third must keep its place")
        await_graph
        assert_kind_of Numeric, screen_position(alone)["x"]
      end
    ensure
      page.execute_script("if (window.RealWorker) { window.Worker = window.RealWorker; delete window.RealWorker }")
    end
  end

  # `roundRect` is newer than the rest of what the canvas draws. Without it
  # the badge is a plain rectangle, and the graph is drawn all the same: a
  # throw inside the draw took the whole canvas down (and fails this test,
  # as any JavaScript error does).
  test "a browser without roundRect still draws the graph, and a noted post's badge as a rectangle" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path
    await_graph
    bare = notes_badge_pixel(a)
    as(users(:two)) { Notes::Start.call(a, body: "Check the dates") }
    script = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: "delete CanvasRenderingContext2D.prototype.roundRect")

    visit admin_mind_graph_path
    await_graph

    assert_equal "undefined", page.evaluate_script("typeof CanvasRenderingContext2D.prototype.roundRect")
    assert_not_equal bare, notes_badge_pixel(a), "no notes badge at the node's top-left"
    click_node(a)
    assert_selector "[data-mind-graph-card] [data-mind-graph-card-notes] li[data-note-row]", text: "Check the dates"
  ensure
    page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: script["identifier"]) if script
  end
end
