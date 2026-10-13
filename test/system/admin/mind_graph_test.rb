require "application_system_test_case"

# The Mind graph (mind graph canvas spec): drawn on a canvas, so nothing on it
# is an element a test can find. The controller says what it shows through
# data attributes on its element (`data-state`, `data-settled`, `data-nodes`,
# `data-edges`, `data-zoom`, `data-labelled`, `data-selected`, `data-hovered`,
# `data-pinned`) and answers a node's place on screen through
# `element.mindGraph.screenPosition(id)`, where a test then points for real.
#
# A small graph UNFOLDS at one tick a frame, about five seconds from load to
# rest, and eases for about as long after a drop, a filter or an unpin: every
# `await_graph` here waits that out, which is the screen as a person gets it. What a mark LOOKS like is read from the canvas's own pixels
# (`pixel_at`): a canvas can pass every other test and still draw nothing.
class Admin::MindGraphSystemTest < ApplicationSystemTestCase
  GRAPH = "[data-controller~='admin--mind-graph--graph']".freeze
  # The graph's own canvas: the legend's swatches are canvases too.
  CANVAS = "#{GRAPH} canvas[data-admin--mind-graph--graph-target='canvas']".freeze
  LIST = "#{GRAPH} [data-mind-graph-list]".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

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

  # The screen fills the window (the round of 2026-10-08): the box is (almost)
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

  # Pages spec §4, §5: pages, the post type a page lists and All posts are on
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

  # Mind graph canvas spec §5.2: hubs are labelled first and the rest arrive
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

  # Mind graph canvas spec §4.4: with the canvas focused, + and - zoom around
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

  # Pages spec §6: each toggle hides its kind and only its kind, the counts
  # stay what the graph holds, and the list follows. What a toggle shows is
  # written by the change itself, before the layout moves, so nothing here
  # waits for a layout but the first load and the last look.
  test "each toggle of the legend hides its kind and only its kind, and the counts stay" do
    home = root_page
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    a, b, c = 3.times.map { |i| create_post(title: "P#{i}") }
    PostRelation.create!(post: a, related_post: b)
    [ b, c ].each { |post| PostTag.create!(post: post, tag: Tag.find_or_create_by!(name: "t")) }
    tag = Tag.find_by!(name: "t")
    visit admin_mind_graph_path
    await_graph
    counts = [ "Pages 2", "Posts 3", "Tags 1", "Post types 1", "Tree 1", "Lists 1", "Related 1", "Shares a tag 2" ]
    shows = lambda do |nodes, edges|
      assert_selector "#{GRAPH}[data-nodes='#{nodes}'][data-edges='#{edges}']"
      assert_equal counts, legend_counts
    end

    shows.call(7, 5)
    assert_selector "#{GRAPH} input[name=mind_graph_nodes][value=page][aria-label='Pages, 2']", visible: :all
    assert_selector "#{GRAPH} input[name=mind_graph_lines][value=tag][aria-label='Shares a tag, 2']", visible: :all
    assert_selector "#{CANVAS}[aria-label='Mind graph: 2 pages, 1 post type, 3 posts and 1 tag, 5 connections. Showing everything.']"
    assert_no_selector "#{GRAPH} [role=status] [data-mind-graph-announced]", visible: :all

    toggle "Related"
    shows.call(7, 4)
    assert screen_position(a), "a line switched off hid a node"
    assert_selector "#{CANVAS}[aria-label='Mind graph: 2 pages, 1 post type, 3 posts and 1 tag, 4 connections. Showing everything. Related lines hidden.']"
    toggle "Related"

    toggle "Tags"
    shows.call(6, 3)
    assert_nil screen_position(tag)
    within(LIST) { assert_no_selector "h2", text: /tags/i }
    toggle "Tags"

    toggle "Post types"
    shows.call(6, 4)
    assert_nil screen_position("type-blog")
    toggle "Post types"

    toggle "Lists"
    shows.call(7, 4)
    assert screen_position("type-blog"), "the type stays, without its line"
    toggle "Tree"
    shows.call(7, 3)
    toggle "Lists"
    toggle "Tree"

    toggle "Pages"
    shows.call(5, 3)
    assert_nil screen_position(home)
    assert_selector "#{CANVAS}[aria-label='Mind graph: 1 post type, 3 posts and 1 tag, 3 connections. Showing everything. Pages hidden.']"
    # A change of the legend is announced: the same words in the notice's
    # live region, once, hidden from the eye.
    assert_selector "#{GRAPH} [role=status] p.sr-only[data-mind-graph-announced]", count: 1, visible: :all,
      text: "Mind graph: 1 post type, 3 posts and 1 tag, 3 connections. Showing everything. Pages hidden."
    toggle "Pages"

    shows.call(7, 5)
    await_graph
    assert screen_position(home)
  end

  # The legend by the keyboard: a toggle is a checkbox, a Tab stop that Space
  # switches, and the graph follows it as it follows a click.
  test "Space on a focused toggle switches it" do
    create_post(title: "Alpha", tags: [ "t" ])
    create_post(title: "Beta", tags: [ "t" ])
    visit admin_mind_graph_path
    await_graph
    assert_selector "#{GRAPH}[data-nodes='3'][data-edges='2']"

    find("#{GRAPH} input[name=mind_graph_nodes][value=tag]").execute_script("this.focus()")
    page.driver.browser.keyboard.type(:Space)

    assert_selector "#{GRAPH}[data-nodes='2'][data-edges='0']"
    assert_no_selector "#{GRAPH} input[name=mind_graph_nodes][value=tag]:checked", visible: :all
    page.driver.browser.keyboard.type(:Space)
    assert_selector "#{GRAPH}[data-nodes='3'][data-edges='2']"
    await_graph
  end

  # Third design answers and H6: status is not a filter. The key is a dialog
  # named "Status key" behind the legend's "Status" link, in the chip's words.
  test "the Status key opens from the keyboard as a dialog, and Escape gives the focus back" do
    create_post(title: "Alpha", tags: [ "t" ])
    create_post(title: "Beta", tags: [ "t" ])
    visit admin_mind_graph_path
    await_graph
    key = "dialog#mind-graph-status-key"
    assert_no_selector "#{key}[open]", visible: :all
    before = [ graph["data-nodes"], graph["data-edges"] ]

    button = find("#{GRAPH} [data-mind-graph-legend] button", text: "Status")
    button.execute_script("this.focus()")
    page.driver.browser.keyboard.type(:Enter)

    assert_selector "#{key}[open] h2", text: "Status key"
    assert_equal [ "Live", "Draft", "Scheduled", "Live, unpublished changes", "Live, change scheduled" ], all("#{key} li[data-legend-state]").map { |item| item.text.squish }
    await_js("document.querySelector('#mind-graph-status-key').contains(document.activeElement)")
    assert_no_selector "#{key} .admin-dialog__body input, #{key} .admin-dialog__body button, #{key} .admin-dialog__body a"
    assert_equal before, [ graph["data-nodes"], graph["data-edges"] ], "the key filters nothing"
    # Its five swatches are drawn (by the graph's own renderer), each its own.
    await_js("Array.from(document.querySelectorAll('#mind-graph-status-key canvas[data-swatch]')).every((canvas) => canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data.some((value) => value > 0))")
    drawings = page.evaluate_script("Array.from(document.querySelectorAll('#mind-graph-status-key canvas[data-swatch]'), (canvas) => canvas.toDataURL())")
    assert_equal 5, drawings.uniq.size, "two looks of the key are one drawing"

    page.driver.browser.keyboard.type(:Escape)

    assert_no_selector "#{key}[open]", visible: :all
    await_js("document.activeElement?.textContent.trim() === 'Status'")
    assert_equal before, [ graph["data-nodes"], graph["data-edges"] ], "Escape closed the key and nothing of the graph"
  end

  test "a kind switched off takes the selection, the pins and the hover of its nodes with it, and switched on again brings the node back unpinned" do
    blog = create_page(title: "Blog")
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path
    await_graph
    drag_node(nid(blog), by: [ 60, 40 ])
    await_graph
    click_node(nid(blog))
    assert_equal [ nid(blog), "1" ], [ graph["data-selected"], graph["data-pinned"] ]

    toggle "Pages"

    assert_selector "#{GRAPH}[data-selected=''][data-pinned='0'][data-hovered='']"
    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_no_button "Release 1 pinned"

    toggle "Pages"
    await_graph
    assert screen_position(nid(blog)), "the page did not come back"
    assert_equal "0", graph["data-pinned"], "a pin came back with the node"
  end

  test "with every kind off nothing is drawn and the list says so" do
    create_page(title: "Blog")
    a = create_post(title: "Alpha", tags: [ "t" ])
    create_post(title: "Beta", tags: [ "t" ])
    visit admin_mind_graph_path
    await_graph

    [ "Pages", "Posts", "Tags", "Post types" ].each { |name| toggle name }

    assert_selector "#{GRAPH}[data-nodes='0'][data-edges='0']"
    assert_selector "#{LIST} p", text: "Nothing is drawn yet."
    assert_selector "#{CANVAS}[aria-label='Mind graph: nothing to show. All types are hidden.']"
    assert_nil screen_position(a)
    toggle "Posts"
    assert_selector "#{GRAPH}[data-nodes='2']"
    assert_selector "#{CANVAS}[aria-label='Mind graph: 2 posts, 0 connections. Showing everything. Pages hidden. Tags hidden. Post types hidden.']"
    await_graph
  end

  test "posts with no connection are counted, not drawn" do
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    alone = create_post(title: "Alone")
    visit admin_mind_graph_path
    await_graph

    assert_equal "2", graph["data-nodes"]
    assert_nil screen_position(alone)
    # "Other", and "isn't shown": beside two connected posts the bare "1 post
    # has no connections yet." read as a contradiction.
    assert_text "1 other post has no connections yet and isn't shown."
    assert_no_text "Link posts with Related posts"
  end

  test "posts but no connection at all: the hint, and nothing to draw" do
    2.times { |i| create_post(title: "Alone #{i}") }
    visit admin_mind_graph_path

    assert_selector "#{GRAPH}[data-state='ready'][data-settled]"
    assert_text "Link posts with Related posts, or give them shared tags, to see connections."
    # Nothing is drawn, so there are no "other" posts: the plain sentence.
    assert_text "2 posts have no connections yet."
    assert_no_text "other posts"
    assert_equal "0", graph["data-nodes"]
  end

  test "no readable page or post: 'No pages or posts yet.' and no canvas" do
    visit admin_mind_graph_path

    assert_text "No pages or posts yet."
    assert_no_selector "canvas"
  end

  # Mind graph canvas spec §5.2: cut by code point (an emoji is never halved),
  # and a tag's count is never cut. The labels are drawn, not elements, so the
  # rule is asked of the function that makes them.
  test "a long label is cut with an ellipsis by code point, and a tag keeps its count whole" do
    visit admin_tags_path
    await_admin_controllers

    labels = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("mind_graph/app").then(({ labelFor }) => done([
        labelFor({ kind: "post", title: "Short" }),
        labelFor({ kind: "post", title: "A very long post title that goes on and on and on" }),
        labelFor({ kind: "post", title: "😀".repeat(40) }),
        labelFor({ kind: "tag", title: "a-long-shared-tag-name-for-the-box", count: 3 }),
        labelFor({ kind: "tag", title: "ruby", count: 12 })
      ]))
    JS

    assert_equal "Short", labels[0]
    assert_equal "A very long post title that goe…", labels[1]
    assert_equal 32, labels[1].each_char.size
    assert_equal ("😀" * 31) + "…", labels[2]
    assert_equal "a-long-shared-tag-name-for-… (3)", labels[3]
    assert_equal "ruby (12)", labels[4]
  end

  test "the data can't be loaded: a message with Retry, which loads it" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_tags_path
    await_admin_controllers
    page.execute_script(<<~JS)
      const original = window.fetch
      window.failGraph = true
      window.fetch = (url, options) => (window.failGraph && String(url).includes("/mind_graph/data") ? Promise.reject(new TypeError("Failed to fetch")) : original(url, options))
    JS

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    assert_selector "#{GRAPH}[data-state='failed']"
    assert_text "The graph could not be loaded."
    assert_no_selector "#{GRAPH}[data-settled]"

    page.execute_script("window.failGraph = false")
    press "Retry"
    await_graph
    assert_no_text "The graph could not be loaded."
    assert_equal "3", graph["data-nodes"]
  end

  test "the server refuses the data: the same message" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_tags_path
    await_admin_controllers
    page.execute_script(<<~JS)
      const original = window.fetch
      window.fetch = (url, options) => (String(url).includes("/mind_graph/data") ? Promise.resolve(new Response("", { status: 500 })) : original(url, options))
    JS

    within("nav[aria-label='Modules']") { click_link "Mind graph" }

    assert_selector "#{GRAPH}[data-state='failed']"
    assert_text "The graph could not be loaded."
    assert_button "Retry"
  end

  # Mind graph canvas spec §6: a request that gets no answer is given up after
  # 15 seconds and shown like any other failure. The stubbed request never
  # answers but honours its signal, as `fetch` does; the 15 seconds are made 50
  # milliseconds by handing `AbortSignal.timeout` a shorter one, so nothing
  # here waits out the real time.
  test "the data request gets no answer: it times out into the same message, and Retry loads the graph" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_tags_path
    await_admin_controllers
    page.execute_script(<<~JS)
      const original = window.fetch
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

  # Mind graph canvas spec §5.6. Six thousand posts are not made for this: the
  # endpoint's answer is replaced by one that says it was cut, and the screen
  # has to say so. Every figure in the sentences is grouped, the isolated
  # count too: it is handed to the message as `%{figure}`, and `count` only
  # chooses the plural form.
  test "over the cap the screen says what it shows and what it leaves out" do
    create_post(title: "A")
    visit admin_tags_path
    await_admin_controllers
    stub_graph_data(CAPPED_GRAPH)

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_graph

    assert_text "Showing the 2,000 best-connected of 6,000 posts."
    assert_text "1,214 other posts have no connections yet and aren't shown."
    assert_no_text "Link posts with Related posts"
    assert_equal "2", graph["data-nodes"]
  end

  # A local view is cut differently (`PostGraph::Local#cut`: the nearest posts
  # first, then the better connected), so it has a sentence of its own: "best-
  # connected" would be untrue of it.
  test "over the cap a local view says it shows the nearest posts, not the best-connected" do
    create_post(title: "A")
    visit admin_tags_path
    await_admin_controllers
    stub_graph_data(CAPPED_LOCAL_GRAPH)

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_graph

    assert_text "Showing the 2,000 nearest of 2,695 posts around this one."
    assert_no_text "best-connected"
    assert_equal "2", graph["data-nodes"]
  end

  # The ruling on Task 5's review: Home is held at the centre in the whole
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

  # One number is three nodes (pages spec, decision 4): the post, the tag
  # and the page of id 12 are each drawn, each selected by its own id, with
  # its own neighbours. A page's card and a pill's are their name and Pin
  # until each has its own (pages plan, Task 8). The pill is as wide as its
  # words, is pressed on its box and not on a circle as wide as it, and has
  # no label beside it, hovered or not.
  test "a post, a tag and a page of one database id are three nodes, and a page, a type and a pill are drawn and pressed" do
    create_post(title: "A")
    visit admin_tags_path
    await_admin_controllers
    stub_graph_data(SHARED_ID_GRAPH)
    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_graph

    assert_equal [ "6", "6" ], [ graph["data-nodes"], graph["data-edges"] ], "two posts, the tag, the page, the type and the pill; every line the data holds"
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
    mouse.click(x: pill["x"] + (width / 2) - 2, y: pill["y"] + 5)
    assert_equal "more-type-blog", graph["data-selected"]
    assert_selector "[data-mind-graph-card] h2", exact_text: "+1,980 more"
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
    visit admin_tags_path
    await_admin_controllers
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

  # The numbers in those sentences are written the way the UI's language
  # writes them -- the `@locale` the server's messages name -- and not the way
  # the browser's own locale would. There is no German UI yet, so the test says
  # the messages are German between a failed load and its Retry.
  test "the cap's numbers are formatted for the language of the messages, not the browser's" do
    create_post(title: "A")
    visit admin_tags_path
    await_admin_controllers
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

  test "the worker can't start: a message without Retry, and an error in the console" do
    2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    visit admin_tags_path
    await_admin_controllers

    without_workers do
      within("nav[aria-label='Modules']") { click_link "Mind graph" }

      assert_selector "#{GRAPH}[data-state='worker-failed']"
      assert_text "The graph can't be drawn in this browser."
      assert_no_button "Retry"
      assert_no_selector "#{GRAPH}[data-settled]"
      # Nothing was ever laid out, so nothing is drawn: without positions every
      # node is at 0, 0, and the graph would be a pile in the canvas's corner.
      assert_operator pixel_at(*canvas_box.first(2).map { |edge| edge + 3 })[3], :<, 10, "the unplaced nodes are drawn in the corner"
      # Loud: the failure is a console error, which is what fails any test that
      # did not ask for it.
      expect_js_error(/layout worker.*no workers here/)
    end
  end

  # A node that was never placed is nowhere: every position is still 0, 0, the
  # canvas's top-left corner, and nothing is drawn there -- so nothing may be
  # hovered, clicked or located there either.
  test "the worker can't start: the corner where unplaced nodes would be answers no hover, no click and no position" do
    post = create_post(title: "Alpha", tags: [ "shared" ])
    create_post(title: "Beta", tags: [ "shared" ])
    visit admin_tags_path
    await_admin_controllers
    without_workers do
      within("nav[aria-label='Modules']") { click_link "Mind graph" }
      assert_selector "#{GRAPH}[data-state='worker-failed']"
      expect_js_error(/layout worker.*no workers here/)
    end

    left, top = canvas_box.first(2)
    page.driver.browser.mouse.move(x: left + 3, y: top + 3)
    await_frames
    assert_no_selector "[data-mind-graph-tooltip]", visible: :visible
    page.driver.browser.mouse.click(x: left + 3, y: top + 3)
    await_frames

    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_equal "", graph["data-selected"].to_s
    assert_nil screen_position(post), "an unplaced node has no place on screen"
  end

  # Spec §6: the list is filled before the layout starts, so a worker that
  # fails leaves the nodes reachable. A row opens the node's card -- in the
  # canvas's corner, since no node has a place to stand beside -- and the
  # card's links lead on. There is nothing to pin without a layout.
  test "the worker can't start: the list still gives every node as a row, and its card leads to the node's local view" do
    create_post(title: "Alpha", tags: [ "shared" ])
    create_post(title: "Beta", tags: [ "shared" ])
    tag = Tag.find_by!(name: "shared")
    visit admin_tags_path
    await_admin_controllers

    # The window outlives the visit below: the real worker comes back first.
    without_workers do
      within("nav[aria-label='Modules']") { click_link "Mind graph" }
      assert_selector "#{GRAPH}[data-state='worker-failed']"
      expect_js_error(/layout worker.*no workers here/)
    end

    within(LIST) do
      assert_selector "li", count: 3
      assert_row "Alpha: post, 1 connection. Shows it in the graph."
      assert_row "Beta: post, 1 connection. Shows it in the graph."
      find("button", text: "shared").click
    end
    assert_equal "tag-#{tag.id}", graph["data-selected"]
    within("[data-mind-graph-card]") do
      assert_link "Focus", href: /mind_graph\?tag=#{tag.id}\z/
      assert_no_button "Pin"
    end
    card = element_box("[data-mind-graph-card]")
    box = canvas_box
    assert_in_delta box[2] - 8, card["right"], 1, "with no layout the card stands in the canvas's top-right corner"
    assert_in_delta box[1] + 8, card["top"], 1
    click_frame_link { within("[data-mind-graph-card]") { click_link "Focus" } }
    assert_selector "[data-mind-graph-focus]", text: "Around the tag “shared”"
  end

  # With no layout the list is all there is, so it has to follow the filter:
  # the legend saying "Tags" is off over a list that still holds the tag would be
  # the screen contradicting itself.
  test "the worker can't start: the filter still narrows the list and the counts" do
    a = create_post(title: "Alpha", tags: [ "shared" ])
    create_post(title: "Beta", tags: [ "shared" ])
    PostRelation.create!(post: a, related_post: create_post(title: "Gamma"))
    visit admin_tags_path
    await_admin_controllers
    without_workers do
      within("nav[aria-label='Modules']") { click_link "Mind graph" }
      assert_selector "#{GRAPH}[data-state='worker-failed'][data-nodes='4'][data-edges='3']"
      expect_js_error(/layout worker.*no workers here/)
    end
    assert_selector "#{LIST} li", count: 4

    toggle "Tags"

    assert_selector "#{GRAPH}[data-state='worker-failed'][data-nodes='3'][data-edges='1']"
    within(LIST) do
      assert_selector "li", count: 3
      assert_selector "button", text: "Alpha"
      assert_selector "button", text: "Beta"
      assert_selector "button", text: "Gamma"
      assert_no_selector "button", text: "shared"
    end
    assert_no_selector "#{GRAPH}[data-settled]"
    assert_text "The graph can't be drawn in this browser."
  end

  test "a graph with nothing to draw says so in the list" do
    create_post(title: "Alone")
    visit admin_tags_path
    await_admin_controllers
    stub_graph_data("({ nodes: [], tags: [], edges: [], total: 0, shown: 0, isolated: 0 })")

    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_graph

    within(LIST) do
      assert_text "Nothing is drawn yet."
      assert_no_selector "li"
    end
  end

  # Review focus 2. Leaving while the request is out, and leaving while the
  # layout is still running. For the second the graph has to be big enough to
  # be settling for seconds, so the endpoint's answer is replaced by 1,500
  # posts and 30 tags made in the page (`BIG_GRAPH`); the worker is the real one.
  test "leaving while the graph is loading or settling raises nothing and stops the worker" do
    create_post(title: "A")
    visit admin_tags_path
    await_admin_controllers
    count_workers
    page.execute_script(<<~JS)
      const original = window.fetch
      window.holdGraph = true
      window.heldRequests = 0
      window.abortedRequests = 0
      window.fetch = (url, options) => {
        if (!window.holdGraph || !String(url).includes("/mind_graph/data")) return original(url, options)
        window.heldRequests += 1
        return new Promise((resolve, reject) => options.signal.addEventListener("abort", () => { window.abortedRequests += 1; reject(options.signal.reason) }))
      }
    JS

    # Loading: the request is out when the screen is left, and is aborted.
    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    await_js("window.heldRequests === 1")
    assert_selector "#{GRAPH}[data-state='loading']"
    within("nav[aria-label='Modules']") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    await_js("window.abortedRequests === window.heldRequests")
    assert_equal [ 0, 0 ], page.evaluate_script("[window.startedWorkers, window.liveWorkers]"), "no data, no worker"

    # Settling: a worker was started, is still laying out, and is terminated.
    page.execute_script("window.holdGraph = false")
    stub_graph_data(BIG_GRAPH)
    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    assert_selector "#{GRAPH}[data-state='ready'][data-nodes='1530']", wait: 15
    await_js("window.liveWorkers === 1")
    page.execute_script("window.leftGraph = document.querySelector(#{GRAPH.to_json})")
    within("nav[aria-label='Modules']") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    await_js("window.liveWorkers === 0")
    assert_not page.evaluate_script("window.leftGraph.hasAttribute('data-settled')"), "the layout had cooled down before the screen was left: nothing was stopped"
    assert_operator page.evaluate_script("window.startedWorkers"), :>=, 1
  end

  # Nothing draws after disconnect. The screen is left while the layout of
  # 1,500 nodes is still running (the element that was left never got
  # `data-settled`), so there IS something to stop: frames were being drawn up
  # to the moment of leaving, and none is drawn afterwards.
  test "nothing is drawn once the screen is left" do
    create_post(title: "A")
    visit admin_tags_path
    await_admin_controllers
    stub_graph_data(BIG_GRAPH)
    within("nav[aria-label='Modules']") { click_link "Mind graph" }
    assert_selector "#{GRAPH}[data-state='ready'][data-nodes='1530']", wait: 15
    await_js("document.querySelector(#{GRAPH.to_json}).mindGraph.draws() >= 2")
    page.execute_script(<<~JS)
      window.leftGraph = document.querySelector(#{GRAPH.to_json})
      window.leftDraws = window.leftGraph.mindGraph.draws
      window.drawnAfter = null
      const context = document.querySelector(#{CANVAS.to_json}).getContext("2d")
      const clear = context.clearRect.bind(context)
      context.clearRect = (...args) => { if (window.drawnAfter !== null) window.drawnAfter += 1; clear(...args) }
      // The moment of leaving: Stimulus disconnects the controller when the
      // element goes, and from then on a frame drawn is a frame too many.
      new MutationObserver((_, observer) => {
        if (window.leftGraph.isConnected) return
        observer.disconnect()
        queueMicrotask(() => { window.drawnAfter = 0; window.countAtLeave = window.leftDraws() })
      }).observe(document.documentElement, { childList: true, subtree: true })
    JS

    within("nav[aria-label='Modules']") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    await_js("window.drawnAfter !== null")
    await_frames
    await_frames

    assert_not page.evaluate_script("window.leftGraph.hasAttribute('data-settled')"), "the layout had cooled down before the screen was left: nothing was stopped"
    assert_operator page.evaluate_script("window.countAtLeave"), :>=, 2
    assert_equal [ true, 0 ], page.evaluate_script("[window.leftDraws() === window.countAtLeave, window.drawnAfter]")
    assert page.evaluate_script("window.leftGraph.mindGraph === undefined"), "the element that was left still carries its hook"
  end

  # Review focus 3. Turbo restores the page as it was left -- `data-state=
  # "ready"`, `data-settled`, the counts -- before anything is fetched, so the
  # controller takes those back on connect; `data-url` is fetched once more
  # and the graph drawn from it.
  test "Back to the graph draws it once, with what the legend shows: its counts gone until the data is back, its checkboxes kept" do
    a, b = 2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    PostRelation.create!(post: a, related_post: b)
    visit admin_mind_graph_path
    await_graph
    assert_equal "3", graph["data-nodes"]
    assert_selector "#{CANVAS}[aria-label='Mind graph: 2 posts and 1 tag, 3 connections. Showing everything.']"
    toggle "Tags"
    await_graph
    assert_equal [ "2", "1" ], [ graph["data-nodes"], graph["data-edges"] ]
    assert_selector "#{CANVAS}[aria-label='Mind graph: 2 posts, 1 connection. Showing everything. Tags hidden.']"
    assert_selector "#{GRAPH} [data-mind-graph-announced]", visible: :all

    within("nav[aria-label='Modules']") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    # The data request is counted, and held until `releaseGraph()`: what the
    # restored page says before its data has come is the point of the middle.
    page.execute_script(<<~JS)
      window.graphFetches = 0
      const original = window.fetch
      window.fetch = (url, options) => {
        if (!String(url).includes("/mind_graph/data")) return original(url, options)
        window.graphFetches += 1
        return new Promise((resolve) => { window.releaseGraph = () => resolve(original(url, options)) })
      }
    JS
    page.go_back
    assert_selector "h1", text: "Mind graph"
    await_js("window.graphFetches === 1")
    # The snapshot's canvas was named with the summary of the visit that was
    # left; until this visit's data has come, it has the server's name again.
    # So with the legend: its counts and the names made of them are gone,
    # and the announcement with the notice; the checkboxes are the person's
    # choice and are kept, so "Tags" is still off.
    assert_selector "#{GRAPH}[data-state='loading']"
    assert_selector "#{CANVAS}[aria-label='Mind graph']"
    assert_equal [ "Posts", "Tags", "Related", "Shares a tag" ], legend_counts, "a count of the visit that was left is still beside its toggle"
    assert_no_selector "#{GRAPH} [data-mind-graph-legend] input[aria-label]", visible: :all
    assert_no_selector "#{GRAPH} [data-mind-graph-announced]", visible: :all
    assert_no_selector "#{GRAPH} input[name=mind_graph_nodes][value=tag]:checked", visible: :all
    assert_selector "#{GRAPH} input[name=mind_graph_nodes][value=post]:checked", visible: :all
    page.execute_script("window.releaseGraph()")
    await_graph
    assert_selector "#{CANVAS}[aria-label='Mind graph: 2 posts, 1 connection. Showing everything. Tags hidden.']"
    assert_equal [ "Posts 2", "Tags 1", "Related 1", "Shares a tag 2" ], legend_counts, "the counts are what was loaded, not what the legend shows"

    assert_equal "2", graph["data-nodes"], "Tags is still switched off, so the tag is not drawn"
    assert_equal "1", graph["data-edges"]
    assert_selector CANVAS, count: 1
    # The swatches are drawn again in the restored page: a snapshot keeps a
    # canvas and none of its pixels.
    await_js("Array.from(document.querySelectorAll(#{"#{GRAPH} canvas[data-swatch]".to_json})).every((canvas) => canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data.some((value) => value > 0))")
    assert_equal 1, page.evaluate_script("window.graphFetches")
    box = canvas_box
    [ a, b ].each do |post|
      point = screen_position(post)
      assert point["x"].between?(box[0], box[2]) && point["y"].between?(box[1], box[3]), "#{post.id} is outside the canvas after Back: #{point} in #{box}"
    end
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
    begin
      page.execute_script("document.documentElement.setAttribute('data-theme', #{(theme == "dark" ? "light" : "dark").to_json})")
      await_js("document.querySelector(#{GRAPH.to_json}).mindGraph.draws() > #{draws}")

      assert_not_equal before, pixels_of(posts.first).first, "the post's dot kept the other theme's colour"
    ensure
      page.execute_script("document.documentElement.setAttribute('data-theme', #{theme.to_json})")
    end
  end

  test "a click on a post selects it and opens its card; Open post opens the editor" do
    a = create_post(title: "Alpha", content_type: "resume_entry")
    b = create_post(title: "Beta")
    PostRelation.create!(post: a, related_post: b)
    visit admin_mind_graph_path
    await_graph
    assert_no_selector "[data-mind-graph-card]", visible: :visible

    click_node(a)

    assert_equal nid(a), graph["data-selected"]
    within("[data-mind-graph-card]") do
      assert_text "Alpha"
      assert_text ContentTypes.fetch("resume_entry").label
      assert_text "Live"
      # The counts are in the small upper-case label style, so the text a
      # person reads is upper-case: matched whatever the case.
      assert_text(/1 related\s*·\s*0 tags/i)
      assert_link "Focus", href: /mind_graph\?post=#{a.id}\z/
      assert_button "Pin"
      assert_selector "button[aria-label='Close']", text: "×"
      click_link "Open post"
    end
    assert_current_path admin_post_path(a)
  end

  # In order (the design review of 2026-10-08): the type's dot, the type and
  # the status chip with Close at the end of the row; the title; the counts;
  # then the actions, which are CS Studio's buttons -- the primary one first --
  # and not underlined links. A post's notes stand under the title and its
  # counts and the actions follow them, in the document as on screen (the
  # notes handoff's decision 12).
  test "the card reads top to bottom: kind and status, the title, the two counts, its notes, then its actions as buttons" do
    a = create_post(title: "Alpha", tags: %w[one two])
    b = create_post(title: "Beta", tags: %w[one two])
    PostRelation.create!(post: a, related_post: b)
    PostRelation.create!(post: a, related_post: create_post(title: "Gamma"))
    visit admin_mind_graph_path
    await_graph

    click_node(a)

    card = find("[data-mind-graph-card]")
    # Close is the last child, so Tab meets the actions before it; on screen
    # it stands in the card's top-right corner.
    assert_equal %w[DIV H2 P SECTION DIV BUTTON], card.all(":scope > *").map(&:tag_name).map(&:upcase)
    within(card) do
      assert_selector ":scope > div:first-child span[aria-hidden='true'].rounded-full", count: 2 # the type's dot, the status chip's
      assert_selector ":scope > button:last-child[data-mind-graph-card-close][aria-label='Close']"
      assert_selector "h2", text: "Alpha"
      assert_text(/2 related\s*·\s*2 tags/i)
      assert_equal [ "Open post", "Focus", "Pin" ], all(":scope > div:nth-child(5) > *").map(&:text)
      assert_equal %w[A A BUTTON], all(":scope > div:nth-child(5) > *").map(&:tag_name).map(&:upcase)
      # No visual reordering: the row is drawn where it stands in the document.
      assert_no_selector ":scope > [class~='order-1']"
    end
    # On screen: the counts, the notes, the actions.
    notes = element_box("[data-mind-graph-card] > section")
    assert_operator element_box("[data-mind-graph-card] > p")["bottom"], :<=, notes["top"], "the notes are not under the counts"
    assert_operator notes["bottom"], :<=, element_box("[data-mind-graph-card] > div:nth-child(5)")["top"], "the actions are not under the notes"
    close = element_box("[data-mind-graph-card-close]")
    box = element_box("[data-mind-graph-card]")
    assert_operator box["right"] - close["right"], :<, 12, "Close is not in the card's right corner"
    assert_operator close["top"] - box["top"], :<, 12, "Close is not in the card's top corner"
    styles = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("[data-mind-graph-card] > div:nth-child(5) > *")).map((action) => {
        const style = getComputedStyle(action)
        return { underlined: style.textDecorationLine !== "none", filled: style.backgroundColor, bordered: style.borderTopWidth }
      })
    JS
    assert styles.none? { |style| style["underlined"] }, "an action of the card is an underlined link: #{styles}"
    assert_not_equal styles[1]["filled"], styles[0]["filled"], "Open post is not the primary button"
    assert_equal "1px", styles[1]["bordered"], "Focus is not a secondary button"
  end

  test "a draft's card says Draft" do
    a = create_post(title: "Unfinished", published: false)
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph

    click_node(a)

    assert_selector "[data-mind-graph-card] [data-status='draft']", text: "Draft"
  end

  test "a click on a tag opens its card, with the posts list filtered by it" do
    2.times { |i| create_post(title: "P#{i}", tags: [ "c++ & more" ]) }
    create_post(title: "Untagged")
    tag = Tag.find_by!(name: "c++ & more")
    visit admin_mind_graph_path
    await_graph

    click_node("tag-#{tag.id}")

    within("[data-mind-graph-card]") do
      assert_text "c++ & more"
      assert_text(/2 posts/i)
      assert_link "Focus", href: /mind_graph\?tag=#{tag.id}\z/
      assert_button "Pin"
    end
    click_frame_link { within("[data-mind-graph-card]") { click_link "Show posts with this tag" } }
    assert_current_path admin_posts_path(tag: "c++ & more")
    # The posts list read the name back as it is: the two tagged posts, only.
    assert_text "P0"
    assert_text "P1"
    assert_no_text "Untagged"
  end

  test "a click on empty space, Escape and the card's Close all clear the selection" do
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    corner = page.evaluate_script("(() => { const r = document.querySelector(#{CANVAS.to_json}).getBoundingClientRect(); return [r.left + 6, r.top + 6] })()")

    click_node(a)
    assert_selector "[data-mind-graph-card]"
    page.driver.browser.mouse.click(x: corner[0], y: corner[1])
    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_equal "", graph["data-selected"]

    click_node(a)
    assert_selector "[data-mind-graph-card]"
    escape_on_canvas
    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_equal "", graph["data-selected"]

    click_node(a)
    within("[data-mind-graph-card]") { press "Close" }
    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_equal "", graph["data-selected"]
  end

  test "the selected node and its neighbours are labelled at any zoom" do
    hub = create_post(title: "Hub")
    spokes = 30.times.map { |i| create_post(title: "Spoke #{i}") }
    spokes.each { |spoke| PostRelation.create!(post: hub, related_post: spoke) }
    spokes.each_cons(2) { |a, b| PostRelation.create!(post: a, related_post: b) }
    visit admin_mind_graph_path
    await_graph
    6.times { press "Zoom out" }
    last = spokes.last

    click_node(last)

    # The neighbours are said directly; a neighbour's LABEL may give way to
    # another's where the two would overlap (no overlap wins), the selected
    # node's never does: it places first.
    assert_equal [ hub, spokes[28] ].map { |post| nid(post) }.sort, graph["data-neighbours"].split(",").sort
    await_js("(document.querySelector(#{GRAPH.to_json}).dataset.labelled || '').split(',').includes('#{nid(last)}')")
    assert_equal nid(last), graph["data-labelled"].split(",").first, "the selected node's label is placed first"
  end

  # What dims is everything but the selection and its neighbours: read from the
  # canvas, a far node's mark is fainter than it was and a neighbour's is not.
  test "with a node selected the rest dims, and clearing the selection brings it back" do
    a, b, c, d = %w[A B C D].map { |title| create_post(title: title) }
    PostRelation.create!(post: a, related_post: b)
    PostRelation.create!(post: c, related_post: d)
    visit admin_mind_graph_path
    await_graph
    before = { b => pixels_of(b).first, c => pixels_of(c).first }

    click_node(a)

    assert_equal before[b], pixels_of(b).first, "a neighbour stays at full strength"
    assert_operator pixels_of(c).first[3], :<, before[c][3] / 2, "a node that is neither selected nor a neighbour dims"

    escape_on_canvas
    assert_equal before[c], pixels_of(c).first
  end

  # The neighbours are the ones the SHOWN edges give the selection: a filter
  # change with a node selected recomputes them (`data-neighbours`).
  test "a filter change with a node selected recomputes its neighbours" do
    a, b, c = 3.times.map { |i| create_post(title: "P#{i}", tags: (i < 2 ? [ "shared" ] : [])) }
    PostRelation.create!(post: a, related_post: c)
    tag_id = "tag-#{Tag.find_by!(name: "shared").id}"
    neighbours = -> { graph["data-neighbours"].split(",").sort }
    visit admin_mind_graph_path
    await_graph
    assert_equal "", graph["data-neighbours"].to_s

    click_node(a)
    assert_equal [ nid(c), tag_id ].sort, neighbours.call

    toggle "Shares a tag"
    await_graph
    assert_equal nid(a), graph["data-selected"], "a selection the filter still shows stays"
    assert_selector "[data-mind-graph-card]", text: "P0"
    assert_equal [ nid(c) ], neighbours.call, "the tag is no neighbour while its lines are not shown"
    assert screen_position(tag_id), "a line switched off hides no node"

    toggle "Shares a tag"
    await_graph
    assert_equal [ nid(c), tag_id ].sort, neighbours.call, "with its lines back the tag is a neighbour again"

    escape_on_canvas
    assert_equal "", graph["data-neighbours"]
  end

  test "a filter that hides the selected node clears the selection and closes the card" do
    a, b = 2.times.map { |i| create_post(title: "P#{i}", tags: [ "t" ]) }
    PostRelation.create!(post: a, related_post: b)
    tag = Tag.find_by!(name: "t")
    visit admin_mind_graph_path
    await_graph

    click_node("tag-#{tag.id}")
    assert_selector "[data-mind-graph-card]", text: /2 posts/i

    toggle "Tags"
    await_graph
    assert_equal "", graph["data-selected"]
    assert_no_selector "[data-mind-graph-card]", visible: :visible
  end

  # Review focus 1.
  test "a title with markup in it is text in the card" do
    a = create_post(title: %(</script><img src=x onerror="window.pwned=1"> "quoted" 🎉))
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph

    click_node(a)

    within("[data-mind-graph-card]") { assert_text %(</script><img src=x onerror="window.pwned=1"> "quoted" 🎉) }
    assert_no_selector "[data-mind-graph-card] img", visible: :all
    assert_nil page.evaluate_script("window.pwned")
  end

  test "dragging a node moves it and the selection is not changed by the drag" do
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    from = screen_position(a)
    zoom = graph["data-zoom"]
    record_worker_messages

    mouse = page.driver.browser.mouse
    mouse.move(x: from["x"], y: from["y"])
    mouse.down
    mouse.move(x: from["x"] + 40, y: from["y"] + 30)
    mouse.move(x: from["x"] + 80, y: from["y"] + 60)
    await_js("(() => { const p = document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{nid(a).to_json}); return Math.abs(p.x - #{from["x"] + 80}) < 6 && Math.abs(p.y - #{from["y"] + 60}) < 6 })()")
    # Not a pan, which would move the node on screen just the same: the layout
    # was told to hold the node, and is running again.
    assert_no_selector "#{GRAPH}[data-settled]"
    assert_equal zoom, graph["data-zoom"]
    mouse.up

    assert_equal "", graph["data-selected"].to_s
    assert_no_selector "[data-mind-graph-card]", visible: :visible
    await_graph
    # What the layout was told: the node held (once per move past the click
    # slop), then dropped, once, and nothing after -- no `unpin`: it stays.
    sent = worker_messages
    assert_equal [ "drop" ], sent.last(1), "the drag did not end with one drop: #{sent}"
    assert_operator sent.size, :>=, 2
    assert_equal [ "drag" ], sent[0...-1].uniq, "something other than drags came before the drop: #{sent}"
  end

  # The round of 2026-10-08: "it springs back" was the complaint. A dropped
  # node is pinned -- it is where it was dropped once the layout has come to
  # rest around it -- its neighbour has followed it, it carries the pin mark,
  # and the screen says how many are pinned.
  test "a dropped node stays where it was dropped, its neighbour follows, and it is pinned" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    PostRelation.create!(post: a, related_post: b)
    visit admin_mind_graph_path
    await_graph
    assert_equal "0", graph["data-pinned"]
    assert_no_selector "[data-mind-graph-release]", visible: :visible
    neighbour = screen_position(b)
    unpinned_corner = pin_pixel(a)

    dropped = drag_node(a, by: [ 90, 70 ])
    assert_equal "1", graph["data-pinned"]
    await_graph

    at = screen_position(a)
    assert_in_delta dropped["x"], at["x"], 2, "the node did not stay where it was dropped"
    assert_in_delta dropped["y"], at["y"], 2
    moved = screen_position(b)
    assert_operator Math.hypot(moved["x"] - neighbour["x"], moved["y"] - neighbour["y"]), :>, 20, "the neighbour did not follow the dragged node"
    assert_equal "1", graph["data-pinned"]
    assert_button "Release 1 pinned"
    assert_not_equal unpinned_corner, pin_pixel(a), "no pin mark at the node's top-right"
    assert_selector "[data-legend='pinned']", text: "Pinned"
  end

  # The three ways to let a pinned node go: Unpin in its card, "Release N
  # pinned" beside the zoom buttons, and a double click on it. The card's
  # button also pins a node where it stands, and that moves nothing.
  test "Unpin in the card, Release N pinned and a double click each let a pinned node go" do
    a, b, c = %w[A B C].map { |title| create_post(title: title) }
    PostRelation.create!(post: a, related_post: b)
    PostRelation.create!(post: b, related_post: c)
    visit admin_mind_graph_path
    await_graph

    dropped = drag_node(a, by: [ 110, 60 ])
    await_graph
    click_node(a)
    within("[data-mind-graph-card]") do
      assert_no_button "Pin", exact: true
      press "Unpin"
      assert_button "Pin", exact: true
    end
    assert_equal "0", graph["data-pinned"]
    assert_no_selector "[data-mind-graph-release]", visible: :visible
    await_graph
    freed = screen_position(a)
    assert_operator Math.hypot(freed["x"] - dropped["x"], freed["y"] - dropped["y"]), :>, 5, "an unpinned node stayed exactly where it was held"

    # Pin from the card: where it stands, and nothing moves.
    within("[data-mind-graph-card]") { press "Pin" }
    assert_equal "1", graph["data-pinned"]
    await_graph
    assert_equal freed, screen_position(a)
    within("[data-mind-graph-card]") { assert_button "Unpin" }
    press "Release 1 pinned"
    assert_equal "0", graph["data-pinned"]
    assert_no_selector "[data-mind-graph-release]", visible: :visible
    within("[data-mind-graph-card]") { assert_button "Pin", exact: true }
    await_graph
    escape_on_canvas

    # Two pinned: the button counts them, and a double click frees the one.
    drag_node(a, by: [ 40, 80 ])
    drag_node(c, by: [ -50, 40 ])
    assert_button "Release 2 pinned"
    await_graph
    point = screen_position(c)
    mouse = page.driver.browser.mouse
    mouse.click(x: point["x"], y: point["y"])
    mouse.click(x: point["x"], y: point["y"], count: 2)
    assert_button "Release 1 pinned"
    assert_equal "1", graph["data-pinned"]
    assert_equal nid(c), graph["data-selected"], "the double click's clicks select the node, as any click does"
    await_graph
    press "Release 1 pinned"
    assert_equal "0", graph["data-pinned"]
  end

  # A double click on a node that is not pinned is two clicks and nothing
  # more: the layout is told nothing.
  test "a double click on a node that is not pinned changes nothing" do
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    record_worker_messages
    point = screen_position(a)

    mouse = page.driver.browser.mouse
    mouse.click(x: point["x"], y: point["y"])
    mouse.click(x: point["x"], y: point["y"], count: 2)
    await_frames

    assert_equal nid(a), graph["data-selected"]
    assert_equal [], worker_messages
    assert_equal "0", graph["data-pinned"]
  end

  # Pins are for nodes on screen: the filter keeps those of the nodes that
  # stay (and the node stays put through the new layout) and forgets those of
  # the nodes it hides.
  test "a filter change keeps the pins of the nodes that remain and forgets the others" do
    a, b, c = 3.times.map { |i| create_post(title: "P#{i}") }
    PostRelation.create!(post: a, related_post: b)
    [ b, c ].each { |post| PostTag.create!(post: post, tag: Tag.find_or_create_by!(name: "t")) }
    tag_id = "tag-#{Tag.find_by!(name: "t").id}"
    visit admin_mind_graph_path
    await_graph

    dropped = drag_node(a, by: [ 70, -60 ])
    drag_node(tag_id, by: [ -60, 50 ])
    assert_equal "2", graph["data-pinned"]
    await_graph

    toggle "Tags"
    assert_equal "1", graph["data-pinned"], "the hidden tag's pin was kept"
    assert_button "Release 1 pinned"
    await_graph
    at = screen_position(a)
    assert_in_delta dropped["x"], at["x"], 2, "a pinned node that the filter still shows moved"
    assert_in_delta dropped["y"], at["y"], 2

    toggle "Tags"
    await_graph
    assert_equal "1", graph["data-pinned"], "a pin came back with the node"
  end

  # Pins live in the page that made them. Turbo's snapshot holds the count and
  # the button; Back shows neither, and the new layout holds nothing.
  test "Back to the graph forgets the pins" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    drag_node(a, by: [ 80, 60 ])
    assert_button "Release 1 pinned"
    await_graph

    within("nav[aria-label='Modules']") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    page.go_back
    assert_selector "h1", text: "Mind graph"
    assert_no_selector "#{GRAPH}[data-pinned='1']"
    await_graph

    assert_equal "0", graph["data-pinned"]
    assert_no_selector "[data-mind-graph-release]", visible: :visible
  end

  # The round of 2026-10-08: the card was in a corner, far from what it is
  # about. It stands 22 px from the node's edge, centred on it, and stays
  # there when the view moves: after a pan and after a zoom it is where the
  # node is.
  test "the card opens beside the clicked node and follows it through a pan and a zoom" do
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph

    click_node(a)
    assert_card_beside(a, side: "right")

    box = canvas_box
    mouse = page.driver.browser.mouse
    before = screen_position(a)
    mouse.move(x: box[0] + 200, y: box[3] - 12)
    mouse.down
    mouse.move(x: box[0] + 160, y: box[3] - 42)
    mouse.move(x: box[0] + 120, y: box[3] - 72)
    mouse.up
    await_frames
    assert_in_delta before["x"] - 80, screen_position(a)["x"], 2, "the view did not pan"
    assert_card_beside(a, side: "right")

    zoom = graph["data-zoom"]
    # (A zoom is around the canvas's middle, so it moves the node; the card
    # stands on whichever side has the room there.)
    press "Zoom in"
    await_js("document.querySelector(#{GRAPH.to_json}).dataset.zoom !== #{zoom.to_json}")
    await_frames
    assert_card_beside(a)
    assert_equal nid(a), graph["data-selected"]
  end

  # Near the canvas's right edge there is no room on the right: the card
  # stands left of the node, the same distance away.
  test "the card flips to the node's left near the canvas's right edge" do
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    click_node(a)
    assert_card_beside(a, side: "right")

    # Pan the node to 60 px from the right edge, by a drag on empty space.
    box = canvas_box
    node = screen_position(a)
    shift = box[2] - 60 - node["x"]
    mouse = page.driver.browser.mouse
    mouse.move(x: box[0] + 12, y: box[3] - 12)
    mouse.down
    mouse.move(x: box[0] + 12 + (shift / 2), y: box[3] - 12)
    mouse.move(x: box[0] + 12 + shift, y: box[3] - 12)
    mouse.up
    await_frames

    assert_in_delta box[2] - 60, screen_position(a)["x"], 2
    assert_card_beside(a, side: "left")
    card = element_box("[data-mind-graph-card]")
    assert_operator card["right"], :<, box[2]
  end

  test "the card is out of the way while its own node is dragged, and is back beside it after the drop" do
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    click_node(a)
    assert_selector "[data-mind-graph-card]", visible: :visible

    # Towards the card and over where it stands, in small steps as a hand
    # moves: the first few pixels make the press a drag, which takes the card
    # out of the way before the pointer gets there.
    drag_node(a, by: [ 60, 90 ], release: false, steps: 12)
    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_equal nid(a), graph["data-selected"], "the drag cleared the selection"
    page.driver.browser.mouse.up

    assert_selector "[data-mind-graph-card]", visible: :visible
    await_graph
    assert_card_beside(a, side: "right")
    within("[data-mind-graph-card]") { assert_button "Unpin" }
  end

  # Dot and label are one target: a press on the title is a press on the node.
  # The point is 8 px into the text, 19 px from the centre of a 7 px dot --
  # outside the dot's own 12 px target, so it is the label that answers.
  test "a click on a node's drawn label selects it, and the pointer says it can be clicked" do
    a = create_post(title: "A title long enough to press")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    await_js("(document.querySelector(#{GRAPH.to_json}).dataset.labelled || '').split(',').includes('#{nid(a)}')")
    label = page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.labelBox(#{nid(a).to_json})")
    node = screen_position(a)
    point = [ label["left"] + 12, (label["top"] + label["bottom"]) / 2 ]
    assert_operator point[0] - node["x"], :>, 13, "the point is inside the dot's own target"

    # Past the end of the text is empty canvas: nothing is under the pointer.
    mouse = page.driver.browser.mouse
    mouse.move(x: label["right"] + 8, y: point[1])
    await_frames
    assert_equal "", graph["data-hovered"].to_s
    assert_not_equal "pointer", page.evaluate_script("getComputedStyle(document.querySelector(#{CANVAS.to_json})).cursor")

    mouse.move(x: point[0], y: point[1])
    await_js("document.querySelector(#{GRAPH.to_json}).dataset.hovered === '#{nid(a)}'")
    assert_equal "pointer", page.evaluate_script("getComputedStyle(document.querySelector(#{CANVAS.to_json})).cursor")
    mouse.click(x: point[0], y: point[1])

    assert_equal nid(a), graph["data-selected"]
    assert_selector "[data-mind-graph-card] h2", text: "A title long enough to press"
  end

  # Hover (the round of 2026-10-08): a ring round the mark and the label on a
  # backing -- and nothing else changes. Hovering used to be nothing but a
  # tooltip; dimming the rest is the SELECTION's.
  test "hovering a node rings it and does not dim the others" do
    a, b, c, d = %w[A B C D].map { |title| create_post(title: title) }
    PostRelation.create!(post: a, related_post: b)
    PostRelation.create!(post: c, related_post: d)
    visit admin_mind_graph_path
    await_graph
    point = screen_position(a)
    # 9.5 px left of the centre: outside the 7 px dot, on the hover's ring.
    ring_before = pixel_at(point["x"] - 9.5, point["y"])
    others = [ c, d ].to_h { |post| [ post, pixels_of(post).first ] }

    page.driver.browser.mouse.move(x: point["x"], y: point["y"])
    await_js("document.querySelector(#{GRAPH.to_json}).dataset.hovered === '#{nid(a)}'")

    assert_not_equal ring_before, pixel_at(point["x"] - 9.5, point["y"]), "no ring round the hovered node"
    others.each { |post, pixel| assert_equal pixel, pixels_of(post).first, "#{post.title} changed while another node was hovered" }
    assert_equal "", graph["data-selected"].to_s

    box = canvas_box
    page.driver.browser.mouse.move(x: box[0] + 5, y: box[3] - 5)
    await_js("document.querySelector(#{GRAPH.to_json}).dataset.hovered === ''")
    assert_equal ring_before, pixel_at(point["x"] - 9.5, point["y"])
  end

  # Zoomed far out only the hubs are named. The hovered node's label is shown
  # whatever the ranking says, and goes again when the pointer leaves.
  test "a label the ranking hides is shown for the hovered node" do
    posts = 60.times.map { |i| create_post(title: "Post #{i}", tags: [ "t#{i % 6}" ]) }
    posts.each_cons(2) { |a, b| PostRelation.create!(post: a, related_post: b) }
    visit admin_mind_graph_path
    await_graph
    4.times { press "Zoom out" }
    await_frames
    labelled = graph["data-labelled"].split(",")
    hidden = posts.find { |post| labelled.exclude?(nid(post)) }
    assert hidden, "every post is labelled: nothing to show"

    point = screen_position(hidden)
    page.driver.browser.mouse.move(x: point["x"], y: point["y"])
    await_js("document.querySelector(#{GRAPH.to_json}).dataset.hovered === '#{nid(hidden)}'")
    hovered = nid(hidden)
    await_js("(document.querySelector(#{GRAPH.to_json}).dataset.labelled || '').split(',').includes('#{hovered}')")

    box = canvas_box
    page.driver.browser.mouse.move(x: box[0] + 5, y: box[3] - 5)
    await_js("!(document.querySelector(#{GRAPH.to_json}).dataset.labelled || '').split(',').includes('#{hovered}')")
  end

  # Reduced motion (spec §4.2): the page tells the worker, and the layout is
  # shown ONCE, at rest -- one `tick`, then `settled`. A dragged node moves
  # alone, its neighbours stay put until the drop, and the drop shows the
  # result in one step.
  test "with reduced motion the layout arrives without intermediate frames, and a dragged node moves alone until the drop" do
    a, b, c = %w[A B C].map { |title| create_post(title: title) }
    PostRelation.create!(post: a, related_post: b)
    PostRelation.create!(post: b, related_post: c)
    visit admin_tags_path
    await_admin_controllers
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
    visit admin_tags_path
    await_admin_controllers
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

  test "Escape with the focus inside the card closes it and gives the focus back to the canvas" do
    a = create_post(title: "A")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    click_node(a)

    # The focus is put on a link of the card by script: Cuprite's `send_keys`
    # CLICKS an element that is not focused, and a click here would follow the
    # link (or press Close) and show nothing about the key. The key is real.
    find("[data-mind-graph-card] a", text: "Open post").execute_script("this.focus()")
    assert page.evaluate_script("document.querySelector('[data-mind-graph-card]').contains(document.activeElement)")
    page.driver.browser.keyboard.type(:Escape)

    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_equal "", graph["data-selected"]
    assert page.evaluate_script("document.activeElement === document.querySelector(#{CANVAS.to_json})"), "the focus did not go back to the canvas"
  end

  # A click sends the layout nothing: no `pin`, so no `unpin`, so the graph is
  # not reheated and nothing moves under a pointer that only selected.
  test "a plain click leaves the layout at rest" do
    a = create_post(title: "A")
    b = create_post(title: "B")
    PostRelation.create!(post: a, related_post: b)
    visit admin_mind_graph_path
    await_graph
    before = [ screen_position(a), screen_position(b) ]
    record_worker_messages

    click_node(a)

    assert_selector "[data-mind-graph-card]"
    await_frames
    assert_equal [], worker_messages, "a click sent the layout something"
    assert_selector "#{GRAPH}[data-settled]"
    assert_equal before, [ screen_position(a), screen_position(b) ]
  end

  test "hovering a node shows its full title" do
    long = "A title that is certainly longer than thirty-two characters"
    a = create_post(title: long)
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    point = screen_position(a)

    page.driver.browser.mouse.move(x: point["x"], y: point["y"])

    assert_selector "[data-mind-graph-tooltip]", text: long
    page.driver.browser.mouse.move(x: point["x"] + 200, y: point["y"] + 200)
    assert_no_selector "[data-mind-graph-tooltip]", visible: :visible
  end

  # Turbo's snapshot is the page as it was left, card and all; Back shows a
  # clean screen (the controller's `reset`), and nothing is selected.
  test "Back to the graph after a selection shows no card" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph
    click_node(a)
    click_frame_link { within("[data-mind-graph-card]") { click_link "Open post" } }
    assert_current_path admin_post_path(a)

    page.go_back
    await_graph

    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_equal "", graph["data-selected"].to_s
  end

  test "Focus opens that node's neighbourhood, the depth switch widens it, and Back returns" do
    a, b, c = %w[Alpha Beta Gamma].map { |title| create_post(title: title) }
    PostRelation.create!(post: a, related_post: b)
    PostRelation.create!(post: b, related_post: c)
    visit admin_mind_graph_path
    await_graph

    click_node(a)
    click_frame_link { within("[data-mind-graph-card]") { click_link "Focus" } }

    assert_selector "[data-mind-graph-focus]", text: "Around “Alpha”"
    await_graph
    assert_equal "2", graph["data-nodes"]
    # `data-settled` is written before the frame that writes `data-labelled`.
    assert await_js("(document.querySelector(#{GRAPH.to_json}).dataset.labelled || '').split(',').includes('#{nid(a)}')"), "the focus is always labelled"

    click_frame_link { within("[data-mind-graph-focus]") { click_link "2" } }
    await_graph
    assert_equal "3", graph["data-nodes"]

    page.go_back
    await_graph
    assert_equal "2", graph["data-nodes"]

    click_frame_link { within("[data-mind-graph-focus]") { click_link "Whole graph" } }
    assert_no_selector "[data-mind-graph-focus]"
    await_graph
    assert_equal "3", graph["data-nodes"]
  end

  test "search finds a post the global view does not draw and opens its neighbourhood" do
    a = create_post(title: "Connected")
    PostRelation.create!(post: a, related_post: create_post(title: "Also connected"))
    alone = create_post(title: "Hidden gem")
    visit admin_mind_graph_path
    await_graph
    assert_nil screen_position(alone)

    fill_in "Find a post or tag", with: "hidden"
    click_frame_link { within("[data-mind-graph-results]") { click_link "Hidden gem" } }

    assert_selector "[data-mind-graph-focus]", text: "Around “Hidden gem”"
    await_graph
    assert_equal "1", graph["data-nodes"]
  end

  test "search lists tags too, says when nothing matches, and Escape closes the list" do
    2.times { |i| create_post(title: "P#{i}", tags: [ "ruby" ]) }
    visit admin_mind_graph_path
    await_graph

    fill_in "Find a post or tag", with: "rub"
    within("[data-mind-graph-results]") do
      assert_link "ruby"
      assert_text "Tag"
    end

    assert_selector "[data-mind-graph-status]", text: "1 result", visible: :all

    fill_in "Find a post or tag", with: "zzzz"
    assert_selector "[data-mind-graph-results]", text: "No post or tag matches."
    assert_selector "[data-mind-graph-status]", text: "No post or tag matches.", visible: :all

    find_field("Find a post or tag").send_keys(:escape)
    assert_no_selector "[data-mind-graph-results]", visible: :visible
  end

  test "a result is reached by Tab and opened with Enter" do
    create_post(title: "Hidden gem")
    visit admin_mind_graph_path
    await_graph

    field = find_field("Find a post or tag")
    field.fill_in with: "hidden"
    assert_selector "[data-mind-graph-results] a", text: "Hidden gem"
    click_frame_link { field.send_keys(:tab, :enter) }

    assert_selector "[data-mind-graph-focus]", text: "Around “Hidden gem”"
  end

  test "a failed search says so and the graph keeps working" do
    create_post(title: "Hidden gem")
    visit admin_mind_graph_path
    await_graph
    page.execute_script(<<~JS)
      const original = window.fetch
      window.fetch = (url, options) => String(url).includes("/mind_graph/search") ? Promise.reject(new TypeError("Failed to fetch")) : original(url, options)
    JS

    fill_in "Find a post or tag", with: "hidden"

    assert_selector "[data-mind-graph-results]", text: "Search failed — check your connection."
    assert_selector "[data-mind-graph-status][role=status]", text: "Search failed — check your connection.", visible: :all
    assert_equal "ready", graph["data-state"]
  end

  test "earlier rows are gone as soon as the text changes" do
    create_post(title: "Hidden gem")
    create_post(title: "Zebra")
    visit admin_mind_graph_path
    await_graph
    field = find_field("Find a post or tag")
    field.fill_in with: "hidden"
    assert_selector "[data-mind-graph-results] a", text: "Hidden gem"
    # Hold the next answer back, so what is on screen meanwhile is the point.
    page.execute_script("const original = window.fetch; window.fetch = (url, options) => String(url).includes('/mind_graph/search') ? new Promise(() => {}) : original(url, options)")

    field.send_keys("x")

    assert_no_selector "[data-mind-graph-results] a", visible: :all
  end

  test "Tabbing past the last result closes the list" do
    create_post(title: "Hidden gem")
    visit admin_mind_graph_path
    await_graph
    field = find_field("Find a post or tag")
    field.fill_in with: "hidden"
    assert_selector "[data-mind-graph-results] a", text: "Hidden gem"

    field.send_keys(:tab, :tab)

    assert_no_selector "[data-mind-graph-results]", visible: :visible
    assert_equal "", find("[data-mind-graph-status]", visible: :all).text(:all)
  end

  test "the results are text: a title with markup is not inserted as markup" do
    create_post(title: "<img src=x onerror=alert(1)> gem")
    visit admin_mind_graph_path
    await_graph

    fill_in "Find a post or tag", with: "gem"

    assert_selector "[data-mind-graph-results] a", text: "<img src=x onerror=alert(1)> gem"
    assert_no_selector "[data-mind-graph-results] img", visible: :all
  end

  test "Back to the graph shows no results list and an empty search field" do
    create_post(title: "Hidden gem")
    visit admin_mind_graph_path
    await_graph
    fill_in "Find a post or tag", with: "hidden"
    click_frame_link { within("[data-mind-graph-results]") { click_link "Hidden gem" } }
    assert_selector "[data-mind-graph-focus]"

    page.go_back
    await_graph

    assert_no_selector "[data-mind-graph-results]", visible: :visible
    assert_equal "", find_field("Find a post or tag").value
  end

  test "leaving the screen aborts a search request still in flight" do
    create_post(title: "Hidden gem")
    visit admin_mind_graph_path
    await_graph
    # An answer that never comes, so the request is still open when we leave.
    page.execute_script(<<~JS)
      window.searchSignals = []
      const original = window.fetch
      window.fetch = (url, options) => {
        if (!String(url).includes("/mind_graph/search")) return original(url, options)
        window.searchSignals.push(options.signal)
        return new Promise((_, reject) => options.signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError"))))
      }
    JS
    fill_in "Find a post or tag", with: "hid"
    assert_eventually(wait: 3, message: "the search request was never sent") { page.evaluate_script("window.searchSignals.length") == 1 }

    # Left through a real link (the sidebar's Posts), a Turbo visit: the window,
    # and the signals recorded in it, outlive it.
    click_frame_link { within("nav[aria-label='Modules']") { click_link "Posts" } }

    assert page.evaluate_script("window.searchSignals.every((signal) => signal.aborted)"), "the request was left open after the screen was left"
  end

  # --- notes (notes spec §4.4) ------------------------------------------------

  test "a post with open notes shows them in its card, and a note is started from the card" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    as(users(:two)) { Notes::Start.call(a, body: "Check the dates, @[#{users(:one).id}]") }
    visit admin_mind_graph_path
    await_graph
    click_node(a)

    assert_selector "[data-mind-graph-card] [data-mind-graph-card-notes] li[data-note-row][data-unread]", text: "Check the dates"
    # The heading is in the small upper-case label style: matched whatever the case, as the card's counts are.
    assert_selector "[data-mind-graph-card-notes] h3", text: /open notes · 1/i
    # Unread is said in words too, for whoever does not see the ink and the dot.
    assert_selector "[data-mind-graph-card-notes] li[data-note-row][data-unread] .sr-only", text: "new", visible: :all
    # The row leads into the post's editor with the drawer open at that thread.
    thread = Notes::Thread.order(:id).last
    assert_selector "[data-mind-graph-card-notes] li[data-note-row] a[href$='/posts/#{a.id}?notes=open&thread=#{thread.id}']"
    within("[data-mind-graph-card-notes]") do
      find("textarea").send_keys("And the prices")
      press "Add note"
    end

    assert_selector "[data-mind-graph-card-notes] li[data-note-row]", count: 2
    assert_selector "[data-mind-graph-card-notes] h3", text: /open notes · 2/i
    assert_selector "[data-mind-graph-card-notes] li[data-note-row]:not([data-unread])", count: 1
    assert_selector "[data-mind-graph-card-notes] .sr-only", count: 1, visible: :all # the viewer's own note is not "new"
    assert_equal "", find("[data-mind-graph-card-notes] textarea").value
    assert_equal [ "mind_graph", a ], Notes::Thread.order(:id).last.then { |started| [ started.origin_view, started.subject ] }
    # Listing a post's notes in the card read none of them (decision P10).
    assert_equal 1, Notes::Delivery.unread.where(user: users(:one)).count
  end

  # Live delivery (notes spec §6): the card's notes are a part that draws
  # itself, so `admin--notes--live` only tells it that the post's notes changed.
  test "the card's notes follow a note started elsewhere, and the tab's own note is not fetched twice" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path
    await_graph
    click_node(a)
    assert_selector "[data-mind-graph-card-notes][data-admin--notes--live-target=record][data-notes-type=post][data-notes-id='#{a.id}'] textarea"
    assert_no_selector "[data-mind-graph-card-notes] li[data-note-row]"
    await_notes_live

    as(users(:two)) { assert Notes::Start.call(a, body: "Started elsewhere").ok? }

    assert_selector "[data-mind-graph-card-notes] li[data-note-row]", text: "Started elsewhere", wait: 8
    assert_selector "[data-mind-graph-card-notes] h3", text: /open notes · 1/i

    # The card's own note names this tab, so its signal is not answered with
    # a second read of the list: one GET, the card's own after the save.
    page.execute_script(<<~JS)
      window.__noteReads = 0
      const original = window.fetch
      window.fetch = (...args) => {
        if (String(args[0].url || args[0]).includes("/notes/post/") && !args[1]?.method) window.__noteReads += 1
        return original(...args)
      }
    JS
    within("[data-mind-graph-card-notes]") do
      find("textarea").send_keys("From the graph")
      press "Add note"
    end
    assert_selector "[data-mind-graph-card-notes] li[data-note-row]", count: 2
    sleep 0.8 # sleep: the coalescing window (500 ms) must have passed before "it was not fetched again" means anything
    assert_equal 1, page.evaluate_script("window.__noteReads")

    # The card closed: its subscription is let go, and the page stays live.
    escape_on_canvas
    assert_no_selector "[data-mind-graph-card-notes]"
    await_js("document.body.dataset.notesLive === 'connected'")
  end

  test "three notes in the card, then a link to the rest; a post without notes has only the field" do
    a = create_post(title: "Alpha")
    b = create_post(title: "Beta")
    PostRelation.create!(post: a, related_post: b)
    as(users(:two)) { 5.times { |index| Notes::Start.call(a, body: "Note #{index}") } }
    visit admin_mind_graph_path
    await_graph

    click_node(a)
    assert_selector "[data-mind-graph-card-notes] li[data-note-row]", count: 3
    assert_selector "[data-mind-graph-card-notes] a[data-note-more][href$='/posts/#{a.id}?notes=open']", text: "+2 more"
    # The notes arrive after the card was first measured: it is measured
    # again, so it still stands whole inside the canvas.
    card = element_box("[data-mind-graph-card]")
    canvas = canvas_box
    assert_operator card["bottom"], :<=, canvas[3] - 7, "the card with its notes reaches below the canvas"
    assert_operator card["top"], :>=, canvas[1] + 7, "the card with its notes reaches above the canvas"

    escape_on_canvas # the open card may stand over the other node
    click_node(b)
    assert_selector "[data-mind-graph-card-notes] textarea"
    assert_no_selector "[data-mind-graph-card-notes] li"
    assert_no_selector "[data-mind-graph-card-notes] h3" # zero threads: only the field (handoff)
  end

  # A note's text and its author's name are a person's: written as text.
  test "a note with markup in it is text in the card, and so is its author's name" do
    users(:two).update!(name: "<img src=x onerror='window.pwned = 1'>")
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    as(users(:two)) { Notes::Start.call(a, body: "<img src=x onerror='window.pwned = 2'> see") }
    visit admin_mind_graph_path
    await_graph
    click_node(a)

    assert_selector "[data-mind-graph-card-notes] li[data-note-row]", text: "<img src=x onerror='window.pwned = 2'> see"
    assert_selector "[data-mind-graph-card-notes] li[data-note-row]", text: "<img src=x onerror='window.pwned = 1'>"
    assert_no_selector "[data-mind-graph-card] img", visible: :all
    assert_nil page.evaluate_script("window.pwned")
  end

  # A mention typed by hand of someone who may not read the post (Review
  # Focus 2) is refused by the service; the card says why and keeps the text.
  test "a note the server refuses is answered in the card, and what was typed stays in the field" do
    stranger = User.create!(email_address: "stranger@example.com", password: "password-password", name: "Sam")
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path
    await_graph
    click_node(a)

    within("[data-mind-graph-card-notes]") do
      find("textarea").send_keys("Ask @[#{stranger.id}]")
      press "Add note"
      assert_selector "[role=status]", text: "Someone you mentioned can't see this post."
      assert_equal "Ask @[#{stranger.id}]", find("textarea").value
      assert_no_selector "li"
    end
    assert_equal 0, Notes::Thread.count
  end

  # Escape in the field, a click on the canvas and another node all close the
  # card, and the card is built anew each time: a half-typed note went with
  # it. The field keeps a draft like the composers do, per person and per
  # post (`cs-note-draft:<user id>:graph-Post-<id>`).
  test "a note half typed in the card is back when that post's card opens again, is no other post's, and is gone once sent" do
    a = create_post(title: "Alpha")
    b = create_post(title: "Beta")
    PostRelation.create!(post: a, related_post: b)
    visit admin_mind_graph_path
    await_graph
    key = "cs-note-draft:#{users(:one).id}:graph-Post-#{a.id}"

    click_node(a)
    find("[data-mind-graph-card-notes] textarea").send_keys("Half a thought")
    assert_eventually { page.evaluate_script("JSON.parse(window.sessionStorage.getItem(#{key.to_json}) || '{}').body") == "Half a thought" }
    find("[data-mind-graph-card-notes] textarea").send_keys(:escape)
    assert_no_selector "[data-mind-graph-card]"

    # By the list: a card may stand over the other node on the canvas.
    find("#{LIST} button", text: "Beta").click
    assert_selector "[data-mind-graph-card-notes][data-notes-id='#{b.id}']"
    assert_equal "", find("[data-mind-graph-card-notes] textarea").value

    find("#{LIST} button", text: "Alpha").click
    assert_selector "[data-mind-graph-card-notes][data-notes-id='#{a.id}']"
    assert_equal "Half a thought", find("[data-mind-graph-card-notes] textarea").value

    within("[data-mind-graph-card-notes]") { press "Add note" }
    assert_selector "[data-mind-graph-card-notes] li[data-note-row]", text: "Half a thought"
    assert_equal "", find("[data-mind-graph-card-notes] textarea").value
    assert_nil page.evaluate_script("window.sessionStorage.getItem(#{key.to_json})")

    # Emptied by hand, there is no draft either.
    find("[data-mind-graph-card-notes] textarea").send_keys("x", :backspace)
    assert_nil page.evaluate_script("window.sessionStorage.getItem(#{key.to_json})")
  ensure
    page.execute_script("try { window.sessionStorage.clear() } catch (error) {}")
  end

  # What is typed after "Add note", while the note is on its way, would be
  # wiped with the field: the field is read-only for as long.
  test "the card's field is read-only while its note is on the way" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path
    await_graph
    click_node(a)
    find("[data-mind-graph-card-notes] textarea").send_keys("On its way")
    page.execute_script(<<~JS)
      const original = window.fetch
      window.fetch = (...args) => {
        if (String(args[1]?.method || "GET").toUpperCase() !== "POST" || window.__held) return original(...args)
        window.__held = true
        return new Promise((resolve) => { window.__release = () => resolve(original(...args)) })
      }
    JS

    within("[data-mind-graph-card-notes]") { press "Add note" }
    assert_eventually(message: "the note was never sent") { page.evaluate_script("window.__held === true && typeof window.__release === 'function'") }

    field = find("[data-mind-graph-card-notes] textarea")
    assert field.readonly?, "the card's field can be typed in while its note is on the wire"
    assert_equal "On its way", field.value
    # Still out after 300ms: it says so (the notes handoff's decision 41).
    assert_selector "[data-mind-graph-card-notes] button[type=submit][aria-busy=true][disabled]", text: "Sending…"
    assert page.evaluate_script("document.querySelector('[data-mind-graph-card-notes] textarea').classList.contains('text-dim')")
    page.execute_script("window.__release()")

    assert_selector "[data-mind-graph-card-notes] li[data-note-row]", text: "On its way"
    assert_equal "", find("[data-mind-graph-card-notes] textarea").value
    assert_not find("[data-mind-graph-card-notes] textarea").readonly?
    assert_selector "[data-mind-graph-card-notes] button[type=submit]:not([aria-busy]):not([disabled])", text: "Add note"
    assert_not page.evaluate_script("document.querySelector('[data-mind-graph-card-notes] textarea').classList.contains('text-dim')")
  ensure
    page.execute_script("try { window.sessionStorage.clear() } catch (error) {}")
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

  # The badge is canvas pixels: the corner opposite the pin's holds something
  # else once the post has an open note.
  test "a post with an open note carries a badge on its top-left corner" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path
    await_graph
    bare = notes_badge_pixel(a)

    as(users(:two)) { Notes::Start.call(a, body: "Check the dates") }
    visit admin_mind_graph_path
    await_graph

    assert_not_equal bare, notes_badge_pixel(a), "no notes badge at the node's top-left"
    assert_selector "[data-legend='notes']", text: "Open notes"
  end

  # A second click on the node the card is already about leaves the card as
  # it is: the note being typed in it is not thrown away, and its notes are
  # not fetched again.
  test "clicking the selected node again keeps the card and what is typed in it" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    as(users(:two)) { Notes::Start.call(a, body: "Check the dates") }
    visit admin_mind_graph_path
    await_graph
    click_node(a)
    assert_selector "[data-mind-graph-card-notes] li[data-note-row]", count: 1
    find("[data-mind-graph-card-notes] textarea").send_keys("Half a thought")
    page.execute_script("document.querySelector('[data-mind-graph-card-notes]').dataset.same = 'yes'; window.notesFetches = 0; window.realFetch = window.fetch; window.fetch = (...args) => { if (String(args[0]).includes('/notes/')) window.notesFetches += 1; return window.realFetch(...args) }")

    click_node(a)
    await_frames

    assert_equal nid(a), graph["data-selected"]
    assert_selector "[data-mind-graph-card-notes][data-same='yes']"
    assert_equal "Half a thought", find("[data-mind-graph-card-notes] textarea").value
    assert_equal 0, page.evaluate_script("window.notesFetches"), "the card's notes were fetched again"
  ensure
    page.execute_script("if (window.realFetch) { window.fetch = window.realFetch; delete window.realFetch }") # the window is shared with what follows
  end

  # A note started from the card is on the canvas at once: the node's badge
  # is drawn from the count the card read back, with no reload.
  test "a note started from the card puts the badge on its node" do
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path
    await_graph
    bare = notes_badge_pixel(a)
    click_node(a)
    within("[data-mind-graph-card-notes]") do
      find("textarea").send_keys("Check the dates")
      press "Add note"
    end
    assert_selector "[data-mind-graph-card-notes] li[data-note-row]", count: 1

    assert_not_equal bare, notes_badge_pixel(a), "no notes badge after a note was started from the card"
  end

  private

  # What the endpoint answers for a site over the cap, cut down to two nodes:
  # the counts are the point.
  # A post, a tag and a page of ONE database id (pages spec, decision 4: the
  # three tables count on their own), with a page's lines to a tag and to a
  # post type, and a pill hanging off the type by a `brings` line as in a
  # page's local view.
  SHARED_ID_GRAPH = <<~JS.freeze
    ({
      nodes: [ { id: "post-12", title: "Twelve", type: "blog", colour_index: 1, status: "live", changes: null, change_at: null, listed: true, url: "/twelve", degree: 2, related_count: 1, tag_count: 1, open_notes: 0 },
               { id: "post-13", title: "Thirteen", type: "blog", colour_index: 1, status: "live", changes: null, change_at: null, listed: true, url: "/thirteen", degree: 2, related_count: 1, tag_count: 1, open_notes: 0 } ],
      tags: [ { id: "tag-12", name: "twelve", count: 2, degree: 3 } ],
      pages: [ { id: "page-12", title: "Page twelve", path: "/twelve", depth: 0, home: true, parent: null, order: 0, status: "live", changes: null, change_at: null, url: "/pages/12", degree: 2, child_count: 0, listed_count: 2, open_notes: 0 } ],
      types: [ { id: "type-blog", name: "blog", label: "Blog post", colour_index: 1, count: 2, degree: 1 } ],
      edges: [ { source: "post-12", target: "post-13", kind: "related" }, { source: "post-12", target: "tag-12", kind: "tag" }, { source: "post-13", target: "tag-12", kind: "tag" },
               { source: "page-12", target: "tag-12", kind: "lists" }, { source: "page-12", target: "type-blog", kind: "lists" },
               { source: "type-blog", target: "more-type-blog", kind: "brings" } ],
      more: [ { id: "more-type-blog", count: 1980, page: "page-12", target: "type-blog" } ],
      total: 2, shown: 2, isolated: 0
    })
  JS

  CAPPED_GRAPH = <<~JS.freeze
    ({
      nodes: [ { id: "post-1", title: "One", type: "blog", colour_index: 1, status: "live", url: "/one", degree: 1, related_count: 1, tag_count: 0 }, { id: "post-2", title: "Two", type: "blog", colour_index: 1, status: "live", url: "/two", degree: 1, related_count: 1, tag_count: 0 } ],
      tags: [], edges: [ { source: "post-1", target: "post-2", kind: "related" } ], total: 6000, shown: 2000, isolated: 1214
    })
  JS

  # The same for a local view: the data names its focus, and the walk reached
  # more posts than the cap keeps.
  CAPPED_LOCAL_GRAPH = <<~JS.freeze
    ({
      nodes: [ { id: "post-1", title: "One", type: "blog", colour_index: 1, status: "live", url: "/one", degree: 1, related_count: 1, tag_count: 0 }, { id: "post-2", title: "Two", type: "blog", colour_index: 1, status: "live", url: "/two", degree: 1, related_count: 1, tag_count: 0 } ],
      tags: [], edges: [ { source: "post-1", target: "post-2", kind: "related" } ], total: 2695, shown: 2000,
      focus: { kind: "post", id: 1, node_id: "post-1", title: "One", depth: 2 }
    })
  JS

  # A graph that takes the worker seconds to lay out: 1,500 posts in a chain,
  # each also on one of 30 tags. A JavaScript expression, made in the page.
  BIG_GRAPH = <<~JS.freeze
    (() => {
      const nodes = Array.from({ length: 1500 }, (_, index) => ({ id: `post-${index + 1}`, title: `Post ${index + 1}`, type: "blog", colour_index: 1, status: "live", url: "/post", degree: 3, related_count: 2, tag_count: 1 }))
      const tags = Array.from({ length: 30 }, (_, index) => ({ id: `tag-${index + 1}`, name: `tag ${index + 1}`, count: 50, degree: 50 }))
      const edges = [
        ...nodes.slice(1).map((node, index) => ({ source: `post-${index + 1}`, target: node.id, kind: "related" })),
        ...nodes.map((node, index) => ({ source: node.id, target: `tag-${((index + 1) % 30) + 1}`, kind: "tag" }))
      ]
      return { nodes, tags, edges, total: 1500, shown: 1500, isolated: 0 }
    })()
  JS

  # Answers the data endpoint from the page: `payload` is a JavaScript
  # expression for the graph. Installed on a screen visited BEFORE the Mind
  # graph (the window outlives a Turbo visit), so the graph's first request
  # already gets it. While `window.failGraph` is set the request fails instead.
  def stub_graph_data(payload)
    page.execute_script(<<~JS)
      const original = window.fetch
      window.fetch = (url, options) => {
        if (!String(url).includes("/mind_graph/data")) return original(url, options)
        if (window.failGraph) return Promise.reject(new TypeError("Failed to fetch"))
        return Promise.resolve(new Response(JSON.stringify(#{payload}), { headers: { "Content-Type": "application/json" } }))
      }
    JS
  end

  # Counts the workers started and still alive, on a screen visited before the
  # Mind graph.
  def count_workers
    page.execute_script(<<~JS)
      window.liveWorkers = 0
      window.startedWorkers = 0
      const Real = window.Worker
      window.Worker = class extends Real {
        constructor(...args) { super(...args); window.liveWorkers += 1; window.startedWorkers += 1 }
        terminate() { window.liveWorkers -= 1; super.terminate() }
      }
    JS
  end

  # Mind graph canvas spec §5.7: nothing on a canvas takes focus, so every node
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
    visit admin_tags_path
    await_admin_controllers
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
    # The toggles, then "Status", and every one of them a stop the Tab key
    # makes: none is taken out of the order.
    legend = page.evaluate_script("Array.from(document.querySelectorAll(#{"#{GRAPH} [data-mind-graph-legend] input, #{GRAPH} [data-mind-graph-legend] button".to_json}), (element) => [ element.dataset.name || element.textContent.trim(), element.tabIndex ])")
    assert_equal [ [ "Posts", 0 ], [ "Tags", 0 ], [ "Related", 0 ], [ "Shares a tag", 0 ], [ "Status", 0 ] ], legend
  end

  test "a title with markup in it is text in the list and in the search results" do
    nasty = %(<img src=x onerror="window.pwned=1"> & co)
    a = create_post(title: nasty)
    PostRelation.create!(post: a, related_post: create_post(title: "B"))
    visit admin_mind_graph_path
    await_graph

    within(LIST) { assert_selector "button span.truncate", exact_text: nasty }
    fill_in "Find a post or tag", with: "onerror"
    within("[data-mind-graph-results]") { assert_link nasty }

    assert_no_selector "#{LIST} img, [data-mind-graph-results] img", visible: :all
    assert_nil page.evaluate_script("window.pwned")
  end

  # Escape with the canvas focused. The key is real; the focus is given by
  # script, because Cuprite's `send_keys` CLICKS an element that is not
  # focused -- in its middle, where the card of a centred node now stands.
  def escape_on_canvas
    find(CANVAS).execute_script("this.focus()")
    page.driver.browser.keyboard.type(:Escape)
  end

  # A row of the list by its accessible name (Capybara's button locator does
  # not read `aria-label`).
  def assert_row(name) = assert_selector("button[aria-label=#{name.to_json}]")

  # A real click where the node is drawn.
  def click_node(id)
    point = screen_position(id)
    assert point, "node #{id} is not on screen"
    page.driver.browser.mouse.click(x: point["x"], y: point["y"])
  end

  # Presses the mouse on a node and walks it `by` pixels in two steps, waiting
  # until the node is under the pointer again; releases unless told not to.
  # Answers where the node was dropped, in client coordinates.
  #
  # It first waits for the layout to be AT REST. A node is held where it was
  # grabbed, so one that is still easing (after an earlier drop, a filter, an
  # unpin) has moved on between this helper reading its place and the press
  # reaching the browser, and stays that far from the pointer for the whole
  # drag: on a slow runner that was more than the two pixels allowed below,
  # and "the node is where it was dropped" timed out. A person presses where
  # the node is; a test can only press where it was.
  def drag_node(id, by:, release: true, steps: 1)
    assert_selector "#{GRAPH}[data-settled]", wait: 15
    from = screen_position(id)
    assert from, "node #{id} is not on screen"
    to = { "x" => from["x"] + by[0], "y" => from["y"] + by[1] }
    mouse = page.driver.browser.mouse
    mouse.move(x: from["x"], y: from["y"])
    mouse.down
    mouse.move(x: from["x"] + (by[0] / 2), y: from["y"] + (by[1] / 2), steps: steps)
    mouse.move(x: to["x"], y: to["y"], steps: steps)
    await_js("(() => { const p = document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{nid(id).to_json}); return Math.abs(p.x - #{to["x"]}) < 2 && Math.abs(p.y - #{to["y"]}) < 2 })()")
    mouse.up if release
    to
  end

  # The card stands 22 px from the edge of a node of one connection (a 7 px
  # dot), on the given side, and is vertically centred on it.
  def assert_card_beside(id, side: nil, radius: 7)
    node = screen_position(id)
    card = element_box("[data-mind-graph-card]")
    shown = find("[data-mind-graph-card]")["data-side"]
    assert_equal side, shown if side
    if shown == "right"
      assert_in_delta node["x"] + radius + 22, card["left"], 1.5, "the card is not 22 px right of the node: #{node} #{card}"
    else
      assert_in_delta node["x"] - radius - 22, card["right"], 1.5, "the card is not 22 px left of the node: #{node} #{card}"
    end
    assert_in_delta node["y"], (card["top"] + card["bottom"]) / 2, 1.5, "the card is not centred on the node: #{node} #{card}"
  end

  # An element's box in client coordinates.
  def element_box(selector)
    page.evaluate_script("(() => { const r = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height } })()")
  end

  # The boxes the screen is made of, the window's height and the page's own.
  def layout_boxes
    page.evaluate_script(<<~JS)
      (() => {
        const box = (selector) => { const r = document.querySelector(selector).getBoundingClientRect(); return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height } }
        return {
          box: box(#{GRAPH.to_json}), canvas: box(#{CANVAS.to_json}), list: box(#{LIST.to_json}), search: box("#mind-graph-search"),
          main: document.querySelector("main").getBoundingClientRect().width, viewport: window.innerHeight, page: document.documentElement.scrollHeight
        }
      })()
    JS
  end

  # The canvas's colour where a pinned node's mark is: up and to the right of
  # the centre of a 7 px dot.
  def pin_pixel(post)
    point = screen_position(post)
    pixel_at(point["x"] + 5.04, point["y"] - 5.04)
  end

  # The canvas's colour where a node's notes badge is: up and to the LEFT of
  # the centre of a 7 px dot (the pin's corner is up and to the right).
  def notes_badge_pixel(post)
    point = screen_position(post)
    pixel_at(point["x"] - 5.04, point["y"] - 5.04)
  end

  # The browser says the person prefers reduced motion inside the block, and
  # no longer afterwards: it is shared with the tests that follow.
  def with_reduced_motion
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    yield
  ensure
    page.driver.browser.page.command("Emulation.setEmulatedMedia", features: [])
  end

  # Records the type of every message a worker started from now on sends the
  # page (`tick`, `settled`, `error`), on a screen visited BEFORE the Mind
  # graph: how many steps a layout was shown in.
  def record_worker_answers
    page.execute_script(<<~JS)
      window.workerAnswers = []
      const Real = window.Worker
      window.Worker = class extends Real {
        constructor(...args) { super(...args); this.addEventListener("message", ({ data }) => window.workerAnswers.push(data.type)) }
      }
    JS
  end

  def worker_answers = page.evaluate_script("window.workerAnswers")

  # Records the type of every message the page sends a worker from now on
  # (the prototype's method, so the graph's own worker, already running, is
  # covered): what the layout is TOLD, which no pixel shows.
  def record_worker_messages
    page.execute_script(<<~JS)
      window.workerMessages = []
      const post = Worker.prototype.postMessage
      Worker.prototype.postMessage = function(message, ...rest) { window.workerMessages.push(message?.type); return post.call(this, message, ...rest) }
    JS
  end

  def worker_messages = page.evaluate_script("window.workerMessages")

  def graph = find(GRAPH)

  # A toggle of the legend, by the name on it. No `await_graph` is needed to
  # read what it shows: `data-nodes`, `data-edges`, the list and the canvas's
  # name are written by the change itself, before the layout moves.
  def toggle(name) = find("#{GRAPH} [data-mind-graph-legend] label", text: name).click

  # Each toggle as a person reads it: its name, and its count once written.
  def legend_counts = all("#{GRAPH} label[data-legend-toggle]").map { |label| label.text.squish }

  # The graph is loaded and its layout has cooled down -- and the frame that
  # was asked for when it did has been drawn. `data-settled` is written BEFORE
  # that frame, which is the one that writes `data-zoom` and `data-labelled`
  # for the final fit, so a test that read either straight after the selector
  # could find nothing there yet, or the value of the frame before.
  def await_graph
    assert_selector "#{GRAPH}[data-state='ready'][data-settled]", wait: 15
    await_frames
  end

  # No worker can be started inside the block (the constructor throws, as in a
  # browser that has none), and the real one is back afterwards whatever
  # happened: the window outlives a Turbo visit, and a test that fails halfway
  # must not leave the stub behind.
  def without_workers
    page.execute_script("window.RealWorker = window.Worker; window.Worker = class { constructor() { throw new Error('no workers here') } }")
    yield
  ensure
    page.execute_script("if (window.RealWorker) { window.Worker = window.RealWorker; delete window.RealWorker }")
  end

  # A node's id as the data and the page write it (pages spec, decision 4):
  # of a record (a post, a tag, a page), or the id itself as a string
  # ("post-12", "type-blog"). NEVER of a bare number: 12 is a post, a tag
  # and a page at once, and a helper that read it as a post would press the
  # wrong node for the other two and call it found. A number is refused.
  def nid(node)
    case node
    when String then node
    when ApplicationRecord then "#{node.class.name.underscore}-#{node.id}"
    else raise ArgumentError, "a node is named by its record or by its id as a string (\"post-12\"), not by #{node.inspect}: a bare number names no kind"
    end
  end

  # Where the layout has a node, in graph units (the camera not applied).
  def graph_position(id) = page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.graphPosition(#{nid(id).to_json})")

  def screen_position(id)
    page.evaluate_script("document.querySelector(#{GRAPH.to_json}).mindGraph.screenPosition(#{nid(id).to_json})")
  end

  # The canvas's box in client coordinates: left, top, right, bottom.
  def canvas_box
    page.evaluate_script("(() => { const r = document.querySelector(#{CANVAS.to_json}).getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom] })()")
  end

  # The colour the canvas holds at a client point, as [r, g, b, a]. Read after
  # two frames, so a draw that was asked for has happened.
  def pixel_at(x, y)
    await_frames
    page.evaluate_script(<<~JS)
      (() => {
        const canvas = document.querySelector(#{CANVAS.to_json})
        const box = canvas.getBoundingClientRect()
        const ratio = canvas.width / box.width
        return Array.from(canvas.getContext("2d").getImageData(Math.round((#{x} - box.left) * ratio), Math.round((#{y} - box.top) * ratio), 1, 1).data)
      })()
    JS
  end

  # The canvas's colours at `samples` points evenly round a node's centre,
  # `radius` pixels from it: one read, after the frames `pixel_at` waits for.
  # `quadrant: :left` reads the quarter on the node's left only, where there
  # is no label.
  def ring_pixels(node, radius:, samples:, quadrant: nil)
    point = screen_position(node)
    await_frames
    page.evaluate_script(<<~JS)
      (() => {
        const canvas = document.querySelector(#{CANVAS.to_json})
        const box = canvas.getBoundingClientRect()
        const ratio = canvas.width / box.width
        const context = canvas.getContext("2d")
        return Array.from({ length: #{samples} }, (_, step) => {
          const angle = #{quadrant == :left ? "Math.PI * 0.75 + step * Math.PI / 2 / #{samples}" : "step * 2 * Math.PI / #{samples}"}
          const x = #{point["x"]} + #{radius} * Math.cos(angle), y = #{point["y"]} + #{radius} * Math.sin(angle)
          return Array.from(context.getImageData(Math.round((x - box.left) * ratio), Math.round((y - box.top) * ratio), 1, 1).data)
        })
      })()
    JS
  end

  # A post's mark at its centre and four pixels to the left of it.
  def pixels_of(post)
    point = screen_position(post)
    [ pixel_at(point["x"], point["y"]), pixel_at(point["x"] - 4, point["y"]) ]
  end
end
