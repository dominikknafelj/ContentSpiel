require "application_system_test_case"

class Admin::MindGraphNotesSystemTest < Admin::MindGraphSystemTestCase
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
    # Listing a post's notes in the card read none of them.
    assert_equal 1, Notes::Delivery.unread.where(user: users(:one)).count
  end

  # Live delivery: the card's notes are a part that draws
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
      window.realFetch ??= original
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
    assert_no_selector "[data-mind-graph-card-notes] h3" # zero threads: only the field
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
      window.realFetch ??= original
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
    # Still out after 300ms: it says so.
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
end
