require "application_system_test_case"

class Admin::MindGraphSelectionSystemTest < Admin::MindGraphSystemTestCase
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

  # In order: the type's dot, the type and
  # the status chip with Close at the end of the row; the title; the counts;
  # then the actions, which are CS Studio's buttons -- the primary one first --
  # and not underlined links. A post's notes stand under the title and its
  # counts and the actions follow them, in the document as on screen.
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

  # The card stands next to what it is about. It stands 22 px from the node's edge, centred on it, and stays
  # there when the view moves: after a pan and after a zoom it is where the
  # node is.
  test "the card opens beside the clicked node and follows it through a pan and a zoom" do
    # A canvas with room right of the node for the card, whatever the
    # scrollbar's gutter takes from the window.
    at_window(1600, height: 1400) do
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
  end

  # Near the canvas's right edge there is no room on the right: the card
  # stands left of the node, the same distance away.
  test "the card flips to the node's left near the canvas's right edge" do
    # A canvas with room right of the node for the card, whatever the
    # scrollbar's gutter takes from the window.
    at_window(1600, height: 1400) do
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
    # The side is the one the view leaves room for, and Fit decides where the
    # node is dropped from: not pinned to "right" any more, the card is
    # checked beside the node on whichever side it is shown, and inside the
    # canvas, which is what the side is chosen for.
    assert_card_beside(a)
    assert_operator element_box("[data-mind-graph-card]")["right"], :<=, canvas_box[2], "the card is shown on the side that has room"
    assert_operator element_box("[data-mind-graph-card]")["left"], :>=, canvas_box[0]
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

  # Hover: a ring round the mark and the label on a
  # backing -- and nothing else changes. Dimming the rest is the SELECTION's, not the hover's.
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

  # On a real site: what
  # a page's card says is what the data holds for this viewer, its notes are
  # the page's own, "Open page" is the page's editor, and Enter on a selected
  # page opens it. (Each card's order, the five states of the chip and a
  # retired type's card are held against plain data in the modules test.)
  test "a page's card says its address, state, counts and notes and opens the page, a scheduled change says its day behind a warn dot, and a post type's and All posts' cards say their posts" do
    home = root_page
    blog = create_page(title: "Blog")
    create_page(title: "Archive", parent: blog)
    pending = create_page(title: "Pending")
    ContentBlock.create!(owner: blog, block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    ContentBlock.create!(owner: home, block_type: :post_list, position: 0, settings: {})
    2.times { |index| create_post(title: "Post #{index}") }
    at = 3.days.from_now
    Publishing::Version.take!(pending, live_at: at)
    pending.update_columns(unpublished_changes_at: Time.current) # version: none (a test sets the facts a state is derived from) # changes: none (a test sets the facts a state is derived from)
    day = I18n.l(at, format: :"admin.short")
    assert_equal :live_change_scheduled, Publishing::State.of(pending.reload).state, "the test's page has no change scheduled: it shows nothing"
    state = Publishing::State.of(blog.reload).state
    seen = { live: "Live", live_with_changes: "Live · Unpublished changes" }.fetch(state)
    as(users(:two)) { assert Notes::Start.call(blog, body: "Check the intro").ok? }
    chip = "[data-mind-graph-card] .admin-status-chip"
    dots = -> { all("#{chip} span.rounded-full").map { |dot| dot[:class][/bg-[a-z]+/] } }

    with_reduced_motion do
      visit admin_mind_graph_path
      await_graph

      click_node(nid(blog))
      within("[data-mind-graph-card]") do
        assert_selector "span.text-small", exact_text: "/blog"
        assert_no_match(/mono/i, find("span.text-small", exact_text: "/blog").evaluate_script("getComputedStyle(this).fontFamily"))
        assert_equal seen, find(".admin-status-chip[data-status='#{state}']#{" span[data-chip-seen]" unless state == :live}").text.squish
        assert_selector "h2", exact_text: "Blog"
        assert_text(/1 child page\s*·\s*lists 2 posts/i)
        assert_selector "canvas[data-mark=page][aria-hidden='true']"
        assert_selector "[data-mind-graph-card-notes][data-notes-type=page][data-notes-id='#{blog.id}'] li[data-note-row]", text: "Check the intro"
        assert_selector "[data-mind-graph-card-notes] li[data-note-row] a[href$='/pages/#{blog.id}?notes=open&thread=#{Notes::Thread.order(:id).last.id}']"
        assert_equal [ "Open page", "Focus", "Pin" ], find("[data-mind-graph-card-pin]").find(:xpath, "..").all("a, button").map(&:text)
        assert_link "Open page", href: %r{/cs-studio/pages/#{blog.id}\z}
        assert_link "Focus", href: /mind_graph\?page=#{blog.id}\z/
        # A note started from the card is the page's.
        find("textarea").send_keys("From the graph")
        press "Add note"
        assert_selector "[data-mind-graph-card-notes] li[data-note-row]", count: 2
      end
      assert_marks_drawn "[data-mind-graph-card]"
      assert_selector "#{LIST} button[aria-current='true'][data-node-id='#{nid(blog)}']"
      assert_equal [ [ "Page", blog.id ] ] * 2, Notes::Thread.order(:id).last(2).map { |thread| [ thread.container_type, thread.container_id ] }

      # A live page with a change scheduled: "● Live · ● Change scheduled 14 Oct".
      escape_on_canvas
      click_node(nid(pending))
      assert_equal "Live · Change scheduled #{day}", find("#{chip}[data-status='live_change_scheduled'] span[data-chip-seen]").text.squish
      assert_equal "Live, change scheduled #{day}", find("#{chip} .sr-only", visible: :all).text(:all).squish
      assert_equal %w[bg-ok bg-warn], dots.call, "a warn dot before the second part"

      # A post type a page lists, and "All posts": no link, the posts the viewer reads.
      escape_on_canvas
      click_node("type-blog")
      within("[data-mind-graph-card]") do
        assert_selector "h2", exact_text: ContentTypes.fetch("blog").label
        assert_selector "canvas[data-mark=type][data-mark-of='#{ContentTypes.fetch("blog").colour_index}']"
        assert_text(/2 posts/i)
        assert_no_selector "a"
        assert_selector "button[data-mind-graph-card-pin]", text: "Pin"
      end
      escape_on_canvas
      click_node("all-posts")
      within("[data-mind-graph-card]") do
        assert_selector "h2", exact_text: "All posts"
        assert_selector "canvas[data-mark=type][data-mark-of='all-posts']"
        assert_no_selector "a"
      end

      # Enter on a selected page opens it: the card's own "Open page", pressed.
      escape_on_canvas
      click_node(nid(home))
      assert_selector "[data-mind-graph-card] a[data-mind-graph-card-open]", text: "Open page"
      assert_selector "[data-mind-graph-card] span.text-small", exact_text: "/"
      assert_no_match(/mono/i, find("[data-mind-graph-card] span.text-small", exact_text: "/").evaluate_script("getComputedStyle(this).fontFamily"))
      find(CANVAS).execute_script("this.focus()")
      click_frame_link { page.driver.browser.keyboard.type(:Enter) }
      assert_current_path admin_page_path(home)
    end
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
end
