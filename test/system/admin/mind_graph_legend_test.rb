require "application_system_test_case"

class Admin::MindGraphLegendSystemTest < Admin::MindGraphSystemTestCase
  # Each toggle hides its kind and only its kind, the counts
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

  # A TOGGLE IS A FILTER ON WHAT IS DRAWN, NOT A NEW LAYOUT. The layout is computed once
  # over everything the data holds: switching a kind or a kind of line off or
  # on sends the worker nothing, warms nothing up, and leaves every node --
  # shown or hidden -- exactly where it was, so what is switched back on
  # comes back where it was and nothing that stays leaves the view.
  test "a toggle moves nothing: after each of the eight, off and on again, every node is where it was and the layout was told nothing" do
    home = root_page
    blog = create_page(title: "Blog")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    a, b, c = 3.times.map { |i| create_post(title: "P#{i}") }
    PostRelation.create!(post: a, related_post: b)
    [ b, c ].each { |post| PostTag.create!(post: post, tag: Tag.find_or_create_by!(name: "t")) }
    ids = [ home, blog, a, b, c, Tag.find_by!(name: "t") ].map { |record| nid(record) } + [ "type-blog" ]
    visit admin_mind_graph_path
    await_graph
    places = -> { page.evaluate_script("#{ids.to_json}.map((id) => { const at = document.querySelector(#{GRAPH.to_json}).mindGraph.graphPosition(id); return [ at.x, at.y ] })") }
    on_screen = -> { ids.map { |id| screen_position(id) } }
    before = places.call
    seen = on_screen.call
    box = canvas_box
    assert_equal 7, before.uniq.size, "the layout has not placed the nodes apart"
    record_worker_messages

    [ "Pages", "Posts", "Tags", "Post types", "Tree", "Lists", "Related", "Shares a tag" ].each do |name|
      shown = [ graph["data-nodes"], graph["data-edges"] ]
      toggle name
      assert_no_selector "#{GRAPH}[data-nodes='#{shown[0]}'][data-edges='#{shown[1]}']"
      await_frames
      assert_equal before, places.call, "#{name} off moved a node"
      assert_selector "#{GRAPH}[data-settled]"
      on_screen.call.each_with_index do |point, index|
        next unless point

        assert_equal seen[index], point, "#{name} off: #{ids[index]} is drawn somewhere else"
        assert point["x"].between?(box[0], box[2]) && point["y"].between?(box[1], box[3]), "#{name} off: #{ids[index]} left the view"
      end

      toggle name
      assert_selector "#{GRAPH}[data-nodes='7'][data-edges='5'][data-settled]"
      await_frames
      assert_equal before, places.call, "#{name} on again moved a node"
      assert_equal seen, on_screen.call, "#{name} on again: a node did not come back where it was"
    end

    assert_equal [], worker_messages, "a toggle sent the layout a message"
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

  # Status is not a filter. The key is a dialog
  # named "Status key" behind the legend's "Status key…" button, in the chip's words.
  test "the Status key opens from the keyboard as a dialog, and Escape gives the focus back" do
    create_post(title: "Alpha", tags: [ "t" ])
    create_post(title: "Beta", tags: [ "t" ])
    visit admin_mind_graph_path
    await_graph
    key = "dialog#mind-graph-status-key"
    assert_no_selector "#{key}[open]", visible: :all
    before = [ graph["data-nodes"], graph["data-edges"] ]

    button = find("#{GRAPH} [data-mind-graph-legend] button", text: "Status key…")
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
    await_js("document.activeElement?.textContent.trim() === 'Status key…'")
    assert_equal before, [ graph["data-nodes"], graph["data-edges"] ], "Escape closed the key and nothing of the graph"
  end

  test "a kind switched off takes the selection and the card of its node with it, and switched on again the node is back where it was, pinned as it was and not selected" do
    blog = create_page(title: "Blog")
    a = create_post(title: "Alpha")
    PostRelation.create!(post: a, related_post: create_post(title: "Beta"))
    visit admin_mind_graph_path
    await_graph
    drag_node(nid(blog), by: [ 60, 40 ])
    await_graph
    click_node(nid(blog))
    assert_equal [ nid(blog), "1" ], [ graph["data-selected"], graph["data-pinned"] ]
    dropped = screen_position(nid(blog))

    toggle "Pages"

    assert_selector "#{GRAPH}[data-selected=''][data-pinned='1'][data-hovered='']"
    assert_no_selector "[data-mind-graph-card]", visible: :visible
    assert_nil screen_position(nid(blog))

    toggle "Pages"
    assert_selector "#{GRAPH}[data-selected=''][data-pinned='1']"
    assert_equal dropped, screen_position(nid(blog)), "the page did not come back where it was dropped"
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
    # The canvas's name says what the notice says, not that there are no posts.
    assert_selector "#{CANVAS}[aria-label='Mind graph: nothing to show. 2 posts have no connections yet.']"
    assert_equal "0", graph["data-nodes"]
  end

  test "no readable page or post: 'No pages or posts yet.' and no canvas" do
    visit admin_mind_graph_path

    assert_text "No pages or posts yet."
    assert_no_selector "canvas"
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
end
