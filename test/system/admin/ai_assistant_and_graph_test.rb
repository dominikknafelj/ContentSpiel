require "application_system_test_case"

# Task 9's browser-only behaviour: the token reveal's copy button (and its
# visible select-the-text fallback), the related-posts picker saving
# through the post form's own autosave, the mind graph drawing and opening
# a post, and "Create starter pages" refreshing the tree.
class Admin::AiAssistantAndGraphSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  test "creating a token reveals it once, and back/reload don't show it again" do
    visit admin_api_tokens_path
    await_admin_controllers

    # The group's description sits under the select and follows it.
    assert_selector "#token-group-description", text: access_control_groups(:read_only).description.to_s
    fill_in "Name", with: "claude-desktop"
    select "Admin", from: "Group"
    assert_selector "#token-group-description", text: access_control_groups(:admin).description

    press "Create token"

    assert_selector "#api-token-value", text: /\A\h{64}\z/
    raw = find("#api-token-value").text
    assert_current_path admin_api_tokens_path
    assert_text "Copy this token now. It won't be shown again."
    assert_selector "#api-token-config", text: raw
    assert_selector "table", text: "claude-desktop"

    # No Clipboard API (e.g. plain http off localhost): the text is
    # selected instead, and the status line says so -- no dialog.
    page.execute_script("Object.defineProperty(navigator, 'clipboard', { value: undefined, configurable: true })")
    press "Copy token"
    assert_text "the text is selected"
    assert_equal raw, page.evaluate_script("window.getSelection().toString()").strip

    # Leaving and coming Back refetches the list: the token is gone, its name stays.
    visit admin_root_path
    assert_no_selector "#api-token-value"
    page.go_back
    assert_selector "h1", text: "Connect an AI assistant"
    assert_no_text raw
    assert_selector "table", text: "claude-desktop"

    visit admin_api_tokens_path
    assert_no_text raw
    assert_selector "table", text: "claude-desktop"
  end

  test "the related-posts picker adds and removes through autosave" do
    post_record = create_post(title: "Hub")
    other = create_post(title: "Satellite")

    visit admin_post_path(post_record)
    await_admin_controllers

    find("#post-related_post_ids").send_keys("Sat")
    # A native click (not `press`), the way an editor picks: the list's own
    # mousedown handler keeps focus in the search box, so nothing blurs (and
    # nothing autosaves) before the click lands.
    within("#post-related_post_ids-listbox") { find("[role=option]", text: "Satellite").click }
    assert_selector "[data-controller~='admin--chip-input'] li", text: "Satellite"
    assert_selector "#post-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5
    assert_equal [ other.id ], post_record.post_relations.reload.pluck(:related_post_id)

    find("[data-controller~='admin--chip-input'] button[aria-label='Remove Satellite']").click
    assert_no_selector "[data-controller~='admin--chip-input'] li", text: "Satellite"
    wait_until { post_record.post_relations.reload.empty? }
  end

  test "the mind graph draws every post and a click opens its editor" do
    a = create_post(title: "Alpha")
    b = create_post(title: "Beta")
    PostRelation.create!(post: a, related_post: b)

    visit admin_mind_graph_path
    await_admin_controllers

    assert_selector "svg[data-admin--mind-graph-target=svg] g[data-post-id='#{a.id}'] text", text: "Alpha"
    assert_selector "svg[data-admin--mind-graph-target=svg] line", count: 1

    click_graph_node(b)
    assert_current_path admin_post_path(b)
  end

  # Design pass round 1 (Task 17): the graph used to fill the whole content
  # column and fling nodes past its edge.
  def graph_outside_count
    page.evaluate_script(<<~JS)
      (() => {
        const svg = document.querySelector("svg[data-admin--mind-graph-target=svg]")
        const box = svg.getBoundingClientRect()
        const visible = (el) => el.getClientRects().length > 0
        return Array.from(svg.querySelectorAll("circle, rect, text")).filter(visible).filter((el) => {
          const r = el.getBoundingClientRect()
          return r.left < box.left - 1 || r.right > box.right + 1 || r.top < box.top - 1 || r.bottom > box.bottom + 1
        }).length
      })()
    JS
  end

  test "the mind graph keeps to its box and every node stays inside it" do
    posts = [ "Alpha", "Beta", "Gamma", "Delta", "Epsilon", "A very long post title that goes on and on and on and on, well past sixty characters" ].map { |title| create_post(title: title) }
    posts.each_cons(2) { |a, b| PostRelation.create!(post: a, related_post: b) }
    PostRelation.create!(post: posts.first, related_post: posts.last)
    # Round 3: a tag node (a square) with a long name is held to the same box.
    tag = Tag.create!(name: "A shared tag with a rather long name to cut off")
    posts.last(3).each { |post| PostTag.create!(post: post, tag: tag) }

    visit admin_mind_graph_path
    await_admin_controllers
    assert_selector "svg[data-admin--mind-graph-target=svg] circle.mg-dot", count: posts.size
    assert_selector "svg[data-admin--mind-graph-target=svg] g.mg-tag rect", count: 1
    # The controller sets data-settled once the simulation has cooled down.
    assert_selector "svg[data-settled]", wait: 15

    inside_box = <<~JS
      (() => {
        const svg = document.querySelector("svg[data-admin--mind-graph-target=svg]")
        const box = svg.getBoundingClientRect()
        const outside = Array.from(svg.querySelectorAll("circle, rect")).filter((c) => {
          const r = c.getBoundingClientRect()
          return r.left < box.left - 1 || r.right > box.right + 1 || r.top < box.top - 1 || r.bottom > box.bottom + 1
        }).length
        const labelsOutside = Array.from(svg.querySelectorAll("text")).filter((t) => {
          const r = t.getBoundingClientRect()
          return r.left < box.left - 1 || r.right > box.right + 1
        }).length
        const main = document.querySelector("main").getBoundingClientRect()
        return { width: box.width, mainWidth: main.width, bottom: box.bottom, viewport: window.innerHeight, outside, labelsOutside }
      })()
    JS
    result = page.evaluate_script(inside_box)
    # The box fills the view: (almost) the whole content column wide --
    # main's width minus its padding and the box's border -- and it ends
    # inside the window, so the graph is visible without scrolling.
    assert_operator result["width"], :>=, result["mainWidth"] - 60
    assert_operator result["width"], :<=, result["mainWidth"]
    assert_operator result["bottom"], :<=, result["viewport"]
    assert_equal 0, result["outside"]
    assert_equal 0, result["labelsOutside"]

    # Shrinking the window moves the box; the nodes must follow it in.
    page.current_window.resize_to(700, 800)
    wait_until(timeout: 10) do
      resized = page.evaluate_script(inside_box)
      resized["outside"].zero? && resized["labelsOutside"].zero?
    end
  ensure
    # Cuprite keeps the window size for the rest of the worker's session.
    page.driver.resize(1400, 1400)
  end

  # Round 3 (Task 17): tag nodes are small squares joined to their posts by
  # dashed edges, and the All / Related / Tags filter hides the other kind and
  # the nodes it leaves without an edge -- without throwing any node out of the box.
  test "the mind graph filter hides tag nodes and their edges, and everything stays in the box" do
    a = create_post(title: "Alpha")
    b = create_post(title: "Beta")
    c = create_post(title: "Gamma")
    d = create_post(title: "Delta (tag only)")
    e = create_post(title: "Epsilon (tag only)")
    PostRelation.create!(post: a, related_post: b)
    tag = Tag.create!(name: "a-long-shared-tag-name-for-the-box")
    [ c, d, e ].each { |post| PostTag.create!(post: post, tag: tag) }

    visit admin_mind_graph_path
    await_admin_controllers
    assert_selector "svg[data-admin--mind-graph-target=svg] g.mg-tag", count: 1
    assert_selector "svg[data-admin--mind-graph-target=svg] line.mg-edge-related", count: 1
    assert_selector "svg[data-admin--mind-graph-target=svg] line.mg-edge-tag", count: 3
    assert_selector "svg[data-admin--mind-graph-target=svg] g[data-post-id]", count: 5
    assert_no_selector "[data-mind-graph-empty=no-connections]:not(.hidden)", visible: :all

    choose "Related", allow_label_click: true
    assert_no_selector "svg[data-admin--mind-graph-target=svg] g.mg-tag", visible: :visible
    assert_selector "svg[data-admin--mind-graph-target=svg] line.mg-edge-related", count: 1
    assert_no_selector "svg[data-admin--mind-graph-target=svg] line.mg-edge-tag", visible: :visible
    assert_selector "svg[data-admin--mind-graph-target=svg] g[data-post-id]", count: 2
    assert_selector "svg[data-settled]", wait: 15
    assert_equal 0, graph_outside_count

    choose "Tags", allow_label_click: true
    assert_selector "svg[data-admin--mind-graph-target=svg] g.mg-tag", count: 1
    assert_selector "svg[data-admin--mind-graph-target=svg] line.mg-edge-tag", count: 3
    assert_no_selector "svg[data-admin--mind-graph-target=svg] line.mg-edge-related", visible: :visible
    assert_selector "svg[data-admin--mind-graph-target=svg] g[data-post-id]", count: 3
    assert_selector "svg[data-settled]", wait: 15
    assert_equal 0, graph_outside_count

    choose "All", allow_label_click: true
    assert_selector "svg[data-admin--mind-graph-target=svg] g[data-post-id]", count: 5
    assert_selector "svg[data-settled]", wait: 15
    assert_equal 0, graph_outside_count
  end

  test "the mind graph says there is nothing to connect when no post is linked or tagged" do
    create_post(title: "Alone")

    visit admin_mind_graph_path
    await_admin_controllers

    assert_text "Link posts with Related posts, or give them shared tags, to see connections."
    assert_selector "svg[data-admin--mind-graph-target=svg] g[data-post-id]", count: 1
  end

  test "a draft is drawn as a dashed ring, a live post filled, and nodes are keyboard links" do
    live = create_post(title: "Live one")
    draft = create_post(title: "Draft one")
    draft.update_column(:published_at, nil)
    PostRelation.create!(post: live, related_post: draft)

    visit admin_mind_graph_path
    await_admin_controllers

    assert_selector "svg[data-admin--mind-graph-target=svg] g.mg-node.mg-hollow[data-post-id='#{draft.id}']"
    assert_no_selector "svg[data-admin--mind-graph-target=svg] g.mg-node.mg-hollow[data-post-id='#{live.id}']"
    # The cue is the outline's style, not a colour: dashed for the draft (with
    # its type's hue as a core, the type being one of the first six), solid
    # and filled for the live one.
    dash = ->(post) { page.evaluate_script("getComputedStyle(document.querySelector(\"g[data-post-id='#{post.id}'] .mg-dot\")).strokeDasharray") }
    assert_not_equal "none", dash.call(draft)
    assert_equal "none", dash.call(live)
    assert_selector "g[data-post-id='#{draft.id}'] circle.mg-core"
    assert_no_selector "g[data-post-id='#{live.id}'] circle.mg-core"
    assert_no_selector "svg[data-admin--mind-graph-target=svg] g.mg-tint"
    assert_selector "svg[data-admin--mind-graph-target=svg] g[data-post-id='#{live.id}'][role=link][tabindex='0']"

    page.execute_script("document.querySelector(\"svg[data-admin--mind-graph-target=svg] g[data-post-id='#{draft.id}']\").focus()")
    find("svg[data-admin--mind-graph-target=svg] g[data-post-id='#{draft.id}']").send_keys(:enter)
    assert_current_path admin_post_path(draft)
  end

  # Fix round 1 (I1): Turbo snapshots the graph before `disconnect()`
  # clears it, so Back used to restore the old nodes and draw a second
  # live set on top.
  test "going back to the mind graph draws each node once" do
    a = create_post(title: "Alpha")
    b = create_post(title: "Beta")
    PostRelation.create!(post: a, related_post: b)

    visit admin_mind_graph_path
    await_admin_controllers
    assert_selector "svg[data-admin--mind-graph-target=svg] g[data-post-id='#{a.id}']", count: 1

    click_graph_node(b)
    assert_current_path admin_post_path(b)

    page.go_back
    assert_current_path admin_mind_graph_path
    assert_selector "[data-controller~='admin--mind-graph']"
    # The restored snapshot alone already holds exactly one (stale) copy,
    # so the count only means something once the controller has connected
    # and drawn -- then `wait: 0` so Capybara can't catch a passing moment.
    await_admin_controllers
    assert_selector "svg[data-admin--mind-graph-target=svg] g[data-post-id='#{a.id}']", count: 1, wait: 0
    assert_selector "svg[data-admin--mind-graph-target=svg] g[data-post-id='#{b.id}']", count: 1, wait: 0
    assert_selector "svg[data-admin--mind-graph-target=svg] line", count: 1, wait: 0
  end

  test "create starter pages refreshes the tree" do
    # Starter pages are offered only while Home is the only kept page (design
    # pass bug 4), so this starts from a site with nothing but Home.
    root_page

    visit admin_pages_path # opens Home's editor
    await_admin_controllers
    within("#tree") do
      find("button[aria-label='More page actions']").click
      press "Create starter pages"
    end

    assert_text "Starter pages created"
    within("#tree") { assert_text "Blog" }
  end

  private

  # The force simulation keeps nodes drifting for a while after the first
  # draw; a native click aimed at where a node *was* can land on empty
  # canvas. Waits until the node's position has held still for a moment.
  def click_graph_node(post)
    selector = "svg[data-admin--mind-graph-target=svg] g[data-post-id='#{post.id}']"
    read = -> { page.evaluate_script("document.querySelector(#{selector.to_json}).getAttribute('transform')").to_s.scan(/-?[\d.]+/).map(&:to_f) }
    wait_until(timeout: 10) do
      before = read.call
      sleep 0.2
      after = read.call
      before.any? && before.size == after.size && before.zip(after).all? { |a, b| (a - b).abs < 0.5 }
    end
    find(selector).click
  end

  def wait_until(timeout: 5)
    deadline = Time.current + timeout
    until yield
      raise "condition not met within #{timeout}s" if Time.current > deadline

      sleep 0.05
    end
  end
end
