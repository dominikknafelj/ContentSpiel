require "application_system_test_case"

class Admin::MindGraphDraggingSystemTest < Admin::MindGraphSystemTestCase
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

  # A dropped node does not spring back. A dropped
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
  test "a toggle keeps every pin, also of a node it hides, which comes back pinned where it was dropped" do
    a, b, c = 3.times.map { |i| create_post(title: "P#{i}") }
    PostRelation.create!(post: a, related_post: b)
    [ b, c ].each { |post| PostTag.create!(post: post, tag: Tag.find_or_create_by!(name: "t")) }
    tag_id = "tag-#{Tag.find_by!(name: "t").id}"
    visit admin_mind_graph_path
    await_graph

    drag_node(a, by: [ 70, -60 ])
    drag_node(tag_id, by: [ -60, 50 ])
    assert_equal "2", graph["data-pinned"]
    await_graph
    dropped = [ screen_position(a), screen_position(tag_id) ]

    toggle "Tags"
    assert_selector "#{GRAPH}[data-nodes='3'][data-pinned='2'][data-settled]"
    assert_button "Release 2 pinned"
    assert_nil screen_position(tag_id)
    assert_equal dropped[0], screen_position(a), "a pinned node that is still shown moved"

    toggle "Tags"
    assert_selector "#{GRAPH}[data-nodes='4'][data-pinned='2'][data-settled]"
    assert_equal dropped, [ screen_position(a), screen_position(tag_id) ], "the tag did not come back where it was dropped"
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
end
