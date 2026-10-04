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
    press "Create token"

    assert_selector "#api-token-value", text: /\A\h{64}\z/
    raw = find("#api-token-value").text
    assert_current_path admin_api_tokens_path

    # No Clipboard API (e.g. plain http off localhost): the text is
    # selected instead, and the status line says so -- no dialog.
    page.execute_script("Object.defineProperty(navigator, 'clipboard', { value: undefined, configurable: true })")
    press "Copy token"
    assert_text "the text is selected"
    assert_equal raw, page.evaluate_script("window.getSelection().toString()").strip

    press "Done"
    assert_no_selector "#api-token-value"
    page.go_back
    assert_selector "h1", text: "Connect an AI assistant"
    assert_no_text raw

    visit current_url
    assert_no_text raw
  end

  test "the related-posts picker adds and removes through autosave" do
    post_record = create_post(title: "Hub")
    other = create_post(title: "Satellite")

    visit admin_post_path(post_record)
    await_admin_controllers

    find("#post-related_post_ids").send_keys("Sat")
    # A native click (not `press`), the way an editor picks: its mousedown
    # blurs the search box, whose `focusout` autosaves at once and turns the
    # empty status line into "Saving…" before the mouseup. That line used to
    # take no height while empty, so it pushed the results list down a line
    # mid-click, the mouseup landed off the button, no `click` fired, and
    # the pick was never made (`Admin::SaveStatusComponent` now reserves
    # the line).
    within("#post-related_post_ids-results") { find(:button, "Satellite").click }
    assert_selector "[data-controller~='admin--related-posts'] li", text: "Satellite"
    assert_selector "#post-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5
    assert_equal [ other.id ], post_record.post_relations.reload.pluck(:related_post_id)

    within("[data-controller~='admin--related-posts'] li", text: "Satellite") { press "Remove" }
    assert_text "No related posts yet."
    wait_until { post_record.post_relations.reload.empty? }
  end

  test "the mind graph draws every post and a click opens its editor" do
    a = create_post(title: "Alpha")
    b = create_post(title: "Beta")
    PostRelation.create!(post: a, related_post: b)

    visit admin_mind_graph_path
    await_admin_controllers

    assert_selector "svg g[data-post-id='#{a.id}'] text", text: "Alpha"
    assert_selector "svg line", count: 1

    click_graph_node(b)
    assert_current_path admin_post_path(b)
  end

  # Design pass round 1 (Task 17): the graph used to fill the whole content
  # column and fling nodes past its edge.
  test "the mind graph keeps to its box and every node stays inside it" do
    posts = [ "Alpha", "Beta", "Gamma", "Delta", "Epsilon", "A very long post title that goes on and on and on and on, well past sixty characters" ].map { |title| create_post(title: title) }
    posts.each_cons(2) { |a, b| PostRelation.create!(post: a, related_post: b) }
    PostRelation.create!(post: posts.first, related_post: posts.last)

    visit admin_mind_graph_path
    await_admin_controllers
    assert_selector "svg[data-admin--mind-graph-target=svg] circle", count: posts.size
    # The controller sets data-settled once the simulation has cooled down.
    assert_selector "svg[data-settled]", wait: 15

    inside_box = <<~JS
      (() => {
        const svg = document.querySelector("svg[data-admin--mind-graph-target=svg]")
        const box = svg.getBoundingClientRect()
        const outside = Array.from(svg.querySelectorAll("circle")).filter((c) => {
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

  # Fix round 1 (I1): Turbo snapshots the graph before `disconnect()`
  # clears it, so Back used to restore the old nodes and draw a second
  # live set on top.
  test "going back to the mind graph draws each node once" do
    a = create_post(title: "Alpha")
    b = create_post(title: "Beta")
    PostRelation.create!(post: a, related_post: b)

    visit admin_mind_graph_path
    await_admin_controllers
    assert_selector "svg g[data-post-id='#{a.id}']", count: 1

    click_graph_node(b)
    assert_current_path admin_post_path(b)

    page.go_back
    assert_current_path admin_mind_graph_path
    assert_selector "[data-controller~='admin--mind-graph']"
    # The restored snapshot alone already holds exactly one (stale) copy,
    # so the count only means something once the controller has connected
    # and drawn -- then `wait: 0` so Capybara can't catch a passing moment.
    await_admin_controllers
    assert_selector "svg g[data-post-id='#{a.id}']", count: 1, wait: 0
    assert_selector "svg g[data-post-id='#{b.id}']", count: 1, wait: 0
    assert_selector "svg line", count: 1, wait: 0
  end

  test "create starter pages refreshes the tree" do
    # Starter pages are offered only while Home is the only kept page (design
    # pass bug 4), so this starts from a site with nothing but Home.
    root_page

    visit admin_pages_path
    await_admin_controllers
    within(".admin-empty-state") { press "Create starter pages" }

    assert_text "Starter pages created"
    within("#tree") { assert_text "Blog" }
  end

  private

  # The force simulation keeps nodes drifting for a while after the first
  # draw; a native click aimed at where a node *was* can land on empty
  # canvas. Waits until the node's position has held still for a moment.
  def click_graph_node(post)
    selector = "svg g[data-post-id='#{post.id}']"
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
