require "application_system_test_case"

# Presence in the lists (presence spec §5.1; handoff 9 to 12 and 27): a row
# of the page tree and of the posts list is marked where someone ELSE is
# working on that record, with a count from two people, and the marker
# follows what happens without the list being redrawn. Two people are two
# Capybara sessions. `await_notes_live` waits for the list's subscription too
# (`live/state`), so a signal caused after it is heard.
class Admin::PresenceListsSystemTest < ApplicationSystemTestCase
  LIVE = 8
  LIST = "[data-controller~='admin--presence--list']".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @me = users(:one).tap { |user| user.update!(name: "Olga Braun") }
    @dana = users(:two).tap { |user| user.update!(name: "Dana Weiss") }
    @reader = users(:reader)
    @page = create_page(title: "Pricing")
    @elsewhere = create_page(title: "Elsewhere")
    @post = create_post(title: "Translating Everything With Mobility")
    sign_in_via_form(@me)
  end

  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  # The Pages screen on a page nobody else opens in these tests: its tree
  # lists every page, `@page` among them.
  def open_tree
    visit "/cs-studio/pages/#{@elsewhere.id}"
    await_notes_live
    await_read
  end

  def open_posts
    visit "/cs-studio/posts"
    await_notes_live
    await_read
  end

  # Another person on a record, in a session of their own.
  def join(name, user, path: "/cs-studio/pages/#{@page.id}")
    using_session(name) do
      sign_in_via_form(user)
      visit path
      await_notes_live
      yield if block_given?
    end
  end

  def leave(name) = using_session(name) { visit "/cs-studio/tags" }

  def tree_marker(record = @page) = "#tree [data-presence-marker='page-#{record.id}']"

  def post_marker(record = @post) = "tr#post_#{record.id} th[scope=row] a [data-presence-marker='post-#{record.id}']"

  def shown(marker) = "#{marker}:not([hidden])"

  # The list's own first reading is done (it reads once when its subscription
  # is confirmed): what follows is caused by the test.
  def await_read(times = 1)
    await_js("Number(document.querySelector(#{LIST.to_json})?.dataset.presenceReads || 0) >= #{times}", wait: LIVE)
  end

  def reads = page.evaluate_script("Number(document.querySelector(#{LIST.to_json}).dataset.presenceReads || 0)")

  # One of the script's timings, shortened on its element: read when used.
  def set_timing(name, milliseconds)
    page.execute_script("document.querySelector(#{LIST.to_json}).setAttribute('data-admin--presence--list-#{name}-value', #{milliseconds})")
  end

  # Every request to the `here` address from now on, with when it was sent.
  def watch_fetches
    page.execute_script(<<~JS)
      window.__here = []
      if (!window.__fetch) {
        window.__fetch = window.fetch
        window.fetch = (...args) => {
          if (String(args[0]).includes("/presence/here")) window.__here.push({ at: performance.now(), url: String(args[0]) })
          return window.__fetch(...args)
        }
      }
    JS
  end

  def fetches = page.evaluate_script("window.__here.length")

  # "Presence changed somewhere", as the server says it to every list.
  def signal = ActionCable.server.broadcast(Presence::Signals::LIST, { kind: "presence" })

  def hide_document
    page.execute_script(<<~JS)
      window.__hidden = true
      Object.defineProperty(document, "hidden", { get: () => window.__hidden, configurable: true })
      Object.defineProperty(document, "visibilityState", { get: () => (window.__hidden ? "hidden" : "visible"), configurable: true })
      document.dispatchEvent(new Event("visibilitychange"))
    JS
  end

  def show_document = page.execute_script("window.__hidden = false; document.dispatchEvent(new Event('visibilitychange'))")

  # What a marker looks like, measured.
  def look(marker)
    page.evaluate_script(<<~JS)
      (() => {
        const marker = document.querySelector(#{marker.to_json})
        const [ icon, count ] = [ marker.querySelector("svg"), marker.querySelector("[data-presence-marker-count]") ]
        const before = [ ...marker.parentElement.children ].slice(0, [ ...marker.parentElement.children ].indexOf(marker)).filter((each) => each.getClientRects().length).pop()
        const probe = document.body.appendChild(Object.assign(document.createElement("span"), { className: "text-meta" }))
        const meta = getComputedStyle(probe).color
        probe.remove()
        return {
          icon: [ icon.getBoundingClientRect().width, icon.getBoundingClientRect().height ],
          meta: getComputedStyle(marker).color === meta,
          after: Math.round((marker.getBoundingClientRect().left - before.getBoundingClientRect().right) * 10) / 10,
          count: count.hidden ? null : { text: count.textContent, size: getComputedStyle(count).fontSize, mono: getComputedStyle(count).fontFamily === getComputedStyle(document.querySelector(".font-cs-mono")).fontFamily,
                                         gap: Math.round((count.getBoundingClientRect().left - icon.getBoundingClientRect().right) * 10) / 10 },
          label: marker.querySelector("[data-presence-marker-label]").textContent,
          tip: marker.querySelector("[data-tooltip]").textContent
        }
      })()
    JS
  end

  # The accessible name the browser computes for the first element the
  # selector finds.
  def accessible_name(selector)
    cdp = page.driver.browser.page
    cdp.command("Accessibility.enable")
    object = cdp.command("Runtime.evaluate", expression: "document.querySelector(#{selector.to_json})")
    node = cdp.command("Accessibility.getPartialAXTree", objectId: object.dig("result", "objectId"), fetchRelatives: false)
    node.fetch("nodes").first.dig("name", "value")
  end

  test "the tree's row shows a marker when someone else is on that page, the count from two, and loses it when they leave; the row is never redrawn" do
    open_tree
    assert_selector "#{tree_marker}[hidden]", visible: :all
    assert_selector "#tree [data-presence-marker]", count: Page.kept.count, visible: :all
    page.execute_script("window.__row = document.querySelector('#tree li[data-page-id=\"#{@page.id}\"]'); window.__marker = document.querySelector(#{tree_marker.to_json})")
    set_timing("interval", 600)

    join(:dana, @dana)
    assert_selector shown(tree_marker), wait: LIVE
    # Handoff 9 and 10: the icon at 12px in meta, alone for one person, last
    # of the row's markers and 6px after what stands before it.
    assert_equal({ "icon" => [ 12, 12 ], "meta" => true, "after" => 6, "count" => nil, "label" => "Dana Weiss is here", "tip" => "Dana Weiss is here" }, look(tree_marker))
    # Nobody marks themselves: Dana's own tree marks where I am, not her page.
    using_session(:dana) do
      assert_selector shown(tree_marker(@elsewhere)), wait: LIVE
      assert_selector "#{tree_marker}[hidden]", visible: :all
    end
    # Beside the title's link, never in it, and no Tab stop of its own.
    assert_no_selector "#tree a [data-presence-marker]", visible: :all
    assert_equal 0, page.evaluate_script("[ ...document.querySelectorAll('#tree [data-presence-marker], #tree [data-presence-marker] *') ].filter((each) => each.tabIndex >= 0).length")

    join(:reader, @reader)
    assert_selector "#{shown(tree_marker)} [data-presence-marker-count]", text: "2", exact_text: true, wait: LIVE
    # From two the count, in 11px mono, 4px after the icon; the names in
    # order of arrival.
    assert_equal({ "icon" => [ 12, 12 ], "meta" => true, "after" => 6, "count" => { "text" => "2", "size" => "11px", "mono" => true, "gap" => 4 },
                   "label" => "2 people here: Dana Weiss, reader", "tip" => "2 people here: Dana Weiss, reader" }, look(tree_marker))

    leave(:dana)
    assert_selector "#{shown(tree_marker)} [data-presence-marker-label]", text: "reader is here", exact_text: true, visible: :all, wait: LIVE
    assert_no_selector "#{tree_marker} [data-presence-marker-count]"
    leave(:reader)
    assert_selector "#{tree_marker}[hidden]", visible: :all, wait: LIVE
    assert_equal [ "", "" ], page.evaluate_script("[ document.querySelector(#{tree_marker.to_json} + ' [data-presence-marker-label]').textContent, document.querySelector(#{tree_marker.to_json} + ' [data-tooltip]').textContent ]")
    # The same row and the same marker element all along.
    assert_equal true, page.evaluate_script("window.__row === document.querySelector('#tree li[data-page-id=\"#{@page.id}\"]') && window.__marker === document.querySelector(#{tree_marker.to_json})")
  end

  test "the posts list marks a row on the title's line, 6px after the title and inside the link, and loses the mark when they leave" do
    long = create_post(title: "A title so long that it cannot possibly fit on one line of the posts list's title column " * 3)
    open_posts
    assert_selector "#{post_marker}[hidden]", visible: :all
    set_timing("interval", 600)
    plain = accessible_name("tr#post_#{@post.id} th[scope=row] a")
    assert_match(/\ATranslating Everything With Mobility\s+Not listed\z/, plain)

    join(:dana, @dana, path: "/cs-studio/posts/#{@post.id}")
    assert_selector shown(post_marker), wait: LIVE
    # Handoff 27: right after the title text, 6px after it, on the title's
    # line; the path line under it is where it was.
    assert_equal({ "icon" => [ 12, 12 ], "meta" => true, "after" => 6, "count" => nil, "label" => ", Dana Weiss is here", "tip" => "Dana Weiss is here" }, look(post_marker))
    lines = page.evaluate_script(<<~JS)
      (() => {
        const link = document.querySelector("tr#post_#{@post.id} th[scope=row] a")
        const [ line, path ] = link.children
        const [ title, marker ] = [ line.firstElementChild, line.querySelector("[data-presence-marker]") ]
        const centre = (box) => Math.round(box.top + box.height / 2)
        return { children: link.children.length, sameLine: Math.abs(centre(title.getBoundingClientRect()) - centre(marker.getBoundingClientRect())) <= 1,
                 pathBelow: path.getBoundingClientRect().top >= line.getBoundingClientRect().bottom, path: path.textContent.trim() }
      })()
    JS
    assert_equal({ "children" => 2, "sameLine" => true, "pathBelow" => true, "path" => "Not listed" }, lines)

    # It stays meta while the link is hovered, like the path under it.
    find("tr#post_#{@post.id} th[scope=row] a > span:first-child > span:first-child").hover
    assert_equal true, look(post_marker)["meta"]

    join(:reader, @reader, path: "/cs-studio/posts/#{@post.id}")
    assert_selector "#{shown(post_marker)} [data-presence-marker-count]", text: "2", exact_text: true, wait: LIVE
    assert_equal({ "text" => "2", "size" => "11px", "mono" => true, "gap" => 4 }, look(post_marker)["count"])

    # A long title is cut with an ellipsis before the marker is: the marker
    # keeps its size and stays inside the cell.
    join(:third, @dana, path: "/cs-studio/posts/#{long.id}")
    assert_selector shown(post_marker(long)), wait: LIVE
    cut = page.evaluate_script(<<~JS)
      (() => {
        const line = document.querySelector("tr#post_#{long.id} th[scope=row] a > span")
        const [ title, marker ] = [ line.firstElementChild, line.querySelector("[data-presence-marker]") ]
        const cell = line.closest("th").getBoundingClientRect()
        return { cut: title.scrollWidth > title.clientWidth, ellipsis: getComputedStyle(title).textOverflow, oneLine: title.getBoundingClientRect().height < 30,
                 icon: marker.querySelector("svg").getBoundingClientRect().width, inside: marker.getBoundingClientRect().right <= cell.right,
                 after: Math.round(marker.getBoundingClientRect().left - title.getBoundingClientRect().right) }
      })()
    JS
    assert_equal({ "cut" => true, "ellipsis" => "ellipsis", "oneLine" => true, "icon" => 12, "inside" => true, "after" => 6 }, cut)

    leave(:dana)
    leave(:reader)
    assert_selector "#{post_marker}[hidden]", visible: :all, wait: LIVE
    assert_equal plain, accessible_name("tr#post_#{@post.id} th[scope=row] a")
  end

  # Handoff 27, for a screen reader: the marker's words join the link's
  # accessible name. And nothing interactive is nested in the link.
  test "the posts row's link is named with the people, and stays the row's one link" do
    open_posts
    set_timing("interval", 600)
    join(:dana, @dana, path: "/cs-studio/posts/#{@post.id}")
    assert_selector shown(post_marker), wait: LIVE
    assert_match(/\ATranslating Everything With Mobility\s*, Dana Weiss is here\s+Not listed\z/, accessible_name("tr#post_#{@post.id} th[scope=row] a"))

    join(:reader, @reader, path: "/cs-studio/posts/#{@post.id}")
    assert_selector "#{shown(post_marker)} [data-presence-marker-count]", text: "2", exact_text: true, wait: LIVE
    assert_match(/\ATranslating Everything With Mobility\s*, 2 people here: Dana Weiss, reader\s+Not listed\z/, accessible_name("tr#post_#{@post.id} th[scope=row] a"))
    # The count and the tooltip are for the eye: they are not said twice.
    assert_no_match(/reader.*reader|2\s+,/, accessible_name("tr#post_#{@post.id} th[scope=row] a"))

    row = "tr#post_#{@post.id} th[scope=row]"
    assert_selector "#{row} a", count: 1
    assert_equal 1, page.evaluate_script("[ ...document.querySelectorAll(#{"#{row} *".to_json}) ].filter((each) => each.tabIndex >= 0).length")
    # A press on the marker is a press on the link.
    click_frame_link { find(shown(post_marker)).click }
    assert_selector ".admin-editor-header h1", text: "Translating Everything With Mobility"
  end

  # Handoff 12 and 32: the shared tooltip says the marker's words, the same
  # a screen reader hears, for the pointer; a name is put in the page as the
  # text it is. Handoff 35: where the tree is a column a long bubble may
  # reach past the column, inside the window and on top of the content.
  test "hovering a marker shows its words in the shared tooltip, in the tree and in the posts list, whole and on top, and a name is text" do
    @reader.update!(name: %(<img src=x onerror="window.__owned = true">))
    open_tree
    set_timing("interval", 600)
    join(:dana, @dana)
    join(:reader, @reader)
    assert_selector "#{shown(tree_marker)} [data-presence-marker-count]", text: "2", exact_text: true, wait: LIVE

    assert_no_selector "#{tree_marker} [data-tooltip]"
    find(shown(tree_marker)).hover
    assert_selector "#{tree_marker} [data-tooltip]", text: %(2 people here: Dana Weiss, <img src=x onerror="window.__owned = true">), exact_text: true
    assert_no_selector "#tree [data-presence-marker] img", visible: :all
    assert_nil page.evaluate_script("window.__owned")
    assert_no_selector "#tree [title*='Dana']", visible: :all
    # The bubble is whole: inside the window (the tree's column clips nothing
    # at this width, so it may reach over the column's edge; handoff 18, 30).
    whole = page.evaluate_script("(() => { const tip = document.querySelector(#{tree_marker.to_json} + ' [data-tooltip]').getBoundingClientRect(); return tip.left >= 0 && tip.right <= document.documentElement.clientWidth && tip.width <= 240 })()")
    assert_equal true, whole
    # The tree is a column here (not a drawer), the bubble reaches past it
    # over the content, and it is the bubble that is on top there. The
    # bubble lets the pointer through (`pointer-events: none`), and
    # `elementFromPoint` skips such an element: switched on for the question.
    top = page.evaluate_script(<<~JS)
      (() => {
        const tip = document.querySelector(#{tree_marker.to_json} + " [data-tooltip]")
        const [ box, column ] = [ tip.getBoundingClientRect(), document.querySelector("#tree-column").getBoundingClientRect() ]
        tip.style.pointerEvents = "auto"
        const point = (x) => document.elementFromPoint(x, box.top + box.height / 2) === tip
        const answer = { column: getComputedStyle(document.querySelector("#tree-column")).position !== "fixed", past: box.right > column.right,
                         centre: point(box.left + box.width / 2), overContent: point(box.right - 2), viewport: box.top >= 0 && box.bottom <= document.documentElement.clientHeight }
        tip.style.pointerEvents = ""
        return answer
      })()
    JS
    assert_equal({ "column" => true, "past" => true, "centre" => true, "overContent" => true, "viewport" => true }, top)
    find("main h1").hover
    assert_no_selector "#{tree_marker} [data-tooltip]"

    leave(:dana)
    leave(:reader)
    @reader.update!(name: nil)
    open_posts
    set_timing("interval", 600)
    join(:dana, @dana, path: "/cs-studio/posts/#{@post.id}")
    assert_selector shown(post_marker), wait: LIVE
    find(shown(post_marker)).hover
    assert_selector "#{post_marker} [data-tooltip]", text: "Dana Weiss is here", exact_text: true
    # In the table's scrolling box the bubble is not cut and makes no scroll bar.
    box = page.evaluate_script(<<~JS)
      (() => {
        const tip = document.querySelector(#{post_marker.to_json} + " [data-tooltip]").getBoundingClientRect()
        const table = document.querySelector(#{LIST.to_json})
        const inside = table.getBoundingClientRect()
        return { across: tip.left >= inside.left && tip.right <= inside.right, down: tip.bottom <= inside.bottom,
                 scrolls: table.scrollHeight > table.clientHeight || table.scrollWidth > table.clientWidth }
      })()
    JS
    assert_equal({ "across" => true, "down" => true, "scrolls" => false }, box)
  end

  # Handoff 9: "Away people do not count."
  test "someone who is only away is not marked, and is again once they are back" do
    open_tree
    set_timing("interval", 600)
    join(:dana, @dana)
    assert_selector shown(tree_marker), wait: LIVE

    using_session(:dana) { hide_document }
    assert_selector "#{tree_marker}[hidden]", visible: :all, wait: LIVE
    using_session(:dana) { show_document }
    assert_selector shown(tree_marker), wait: LIVE
  end

  # Review Focus 5: a list does not ask constantly. However many signals
  # arrive, it asks once, and once more for those that came after that
  # reading began, no sooner than the interval after it.
  test "any number of signals within the interval cause one fetch, and one more after it" do
    open_tree
    set_timing("interval", 2500)
    watch_fetches
    before = reads

    6.times { signal }
    await_read(before + 1)
    assert_equal 1, fetches
    # More signals, all inside the interval that the reading opened.
    6.times { signal }
    await_frames
    assert_equal 1, fetches
    await_read(before + 2)
    assert_equal 2, fetches
    gap = page.evaluate_script("window.__here[1].at - window.__here[0].at")
    assert_operator gap, :>=, 2400, "the second reading came #{gap.round}ms after the first, inside the interval"
    # Each asks about every marker the list holds, once.
    asked = page.evaluate_script("new URL(window.__here[1].url, location.href).searchParams.getAll('ids[]')")
    assert_equal Page.kept.pluck(:id).map(&:to_s).sort, asked.sort
    assert_equal "page", page.evaluate_script("new URL(window.__here[1].url, location.href).searchParams.get('kind')")

    # And then nothing: no signal, no reading.
    sleep 3 # sleep: longer than the 2.5s interval, to see that no third reading follows the trailing one
    assert_equal 2, fetches
  end

  # Review Focus 2, in a list: a crashed tab sends no leave and no signal.
  test "a crashed person's marker goes within the stale time without any signal" do
    open_tree
    join(:dana, @dana)
    assert_selector shown(tree_marker), wait: LIVE
    watch_fetches

    # Her tab is gone without a word: its row is no longer kept alive.
    Presence::Mark.where(user_id: @dana.id).find_each { |mark| mark.update_columns(seen_at: (Presence::STALE_AFTER + 1.second).ago) } # version: none (a test of presence)
    await_frames
    assert_selector shown(tree_marker)
    assert_equal 0, fetches

    set_timing("refresh", 700)
    assert_selector "#{tree_marker}[hidden]", visible: :all, wait: LIVE
    assert_operator fetches, :>=, 1
  end

  test "a list fetches nothing while its document is hidden, and once when it is shown" do
    open_tree
    set_timing("interval", 600)
    set_timing("refresh", 700)
    watch_fetches
    hide_document

    join(:dana, @dana)
    4.times { signal }
    sleep 2 # sleep: several refresh ticks (700ms) and intervals (600ms) long, to see that a hidden document asks nothing
    assert_equal 0, fetches
    assert_selector "#{tree_marker}[hidden]", visible: :all

    set_timing("refresh", 60_000)
    before = reads
    show_document
    assert_selector shown(tree_marker), wait: LIVE
    await_read(before + 1)
    assert_equal 1, fetches
  end

  # Handoff 10: the folded tree (the "Pages" menu below 1024px) is the same
  # component, so a row is marked there too.
  test "the marker shows in the folded tree below 1024px" do
    original = page.current_window.size
    page.current_window.resize_to(1000, 900)
    open_tree
    set_timing("interval", 600)
    assert_no_selector "#tree-column"

    join(:dana, @dana)
    find("button[aria-label='Open page tree']").click
    assert_selector "#tree-column[data-open]"
    assert_selector shown(tree_marker), wait: LIVE
    assert_equal [ 12, 12 ], look(tree_marker)["icon"]
    leave(:dana)
    assert_selector "#{tree_marker}[hidden]", visible: :all, wait: LIVE
  ensure
    page.current_window.resize_to(*original)
  end

  # The tree is replaced as a whole by a Turbo Stream after a move and after
  # a page's save: the markers come back from the server, and the list goes
  # on from where it was -- the replacement itself asks nothing.
  test "a tree that is replaced under the list keeps its markers live, and the replacement itself fetches nothing" do
    open_tree
    set_timing("interval", 600)
    join(:dana, @dana)
    assert_selector shown(tree_marker), wait: LIVE
    watch_fetches

    page.execute_script(<<~JS)
      window.__tree = document.getElementById("tree")
      const copy = window.__tree.cloneNode(true)
      copy.setAttribute("data-live-part", "waiting")
      copy.removeAttribute("data-presence-reads")
      const stream = document.createElement("turbo-stream")
      stream.setAttribute("action", "replace")
      stream.setAttribute("target", "tree")
      const template = document.createElement("template")
      template.content.append(copy)
      stream.append(template)
      document.body.append(stream)
    JS
    await_js("document.getElementById('tree') !== window.__tree && document.getElementById('tree').getAttribute('data-live-part') === 'answered'", wait: LIVE)
    await_notes_live
    sleep 1 # sleep: longer than the 500ms a reading waits and the 600ms interval, to see that a replaced tree asks nothing by itself
    assert_equal 0, fetches
    assert_selector shown(tree_marker)

    leave(:dana)
    assert_selector "#{tree_marker}[hidden]", visible: :all, wait: LIVE
    assert_operator fetches, :>=, 1
  end

  test "coming back to a list from Turbo's cache reads who is here now" do
    open_tree
    set_timing("interval", 600)
    join(:dana, @dana)
    assert_selector shown(tree_marker), wait: LIVE

    click_link "Tags"
    assert_selector "main h1", text: "Tags"
    leave(:dana)
    Presence::Mark.where(user_id: @dana.id).delete_all # version: none (a test of presence: she is gone whatever her tab did)
    page.go_back
    assert_selector "#tree"
    await_notes_live
    assert_selector "#{tree_marker}[hidden]", visible: :all, wait: LIVE
  end

  test "a page without a list is live without one, and a list is answered only once its subscription is" do
    visit "/cs-studio/tags"
    await_notes_live
    assert_no_selector LIST, visible: :all

    open_tree
    assert_selector "turbo-frame#tree[data-live-part=answered]"
    open_posts
    assert_selector "#{LIST}[data-live-part=answered][data-admin--presence--list-kind-value=post]"
  end

  # The list is beside the tree's own script and inside no form: it sends
  # nothing through the write queue, and no Turbo request.
  test "a list's readings are plain requests: no Turbo fetch, visit, frame load or stream" do
    open_tree
    set_timing("interval", 600)
    page.execute_script(<<~JS)
      window.__turbo = []
      for (const name of [ "turbo:before-fetch-request", "turbo:visit", "turbo:frame-load", "turbo:before-stream-render", "turbo:before-frame-render" ]) {
        document.addEventListener(name, () => window.__turbo.push(name))
      }
    JS
    watch_fetches

    join(:dana, @dana)
    assert_selector shown(tree_marker), wait: LIVE
    leave(:dana)
    assert_selector "#{tree_marker}[hidden]", visible: :all, wait: LIVE

    assert_operator fetches, :>=, 1
    assert_equal [], page.evaluate_script("window.__turbo")
    # The positive control: the collector does hear Turbo. One real visit,
    # and the same list is no longer empty -- so empty meant "none happened".
    # (A made-up event would not do: Turbo's own listeners read its detail.)
    click_link "Tags"
    assert_selector "main h1", text: "Tags"
    heard = page.evaluate_script("window.__turbo")
    assert_includes heard, "turbo:before-fetch-request"
    assert_includes heard, "turbo:visit"
  end

  # The `here` address answers for at most 500 ids, and the tree has no
  # limit: a longer list asks in several requests, one after the other, and
  # draws when all have answered. The size of a part is shortened here.
  test "a list longer than one request may ask about is asked in parts, one after the other, and every marker is drawn" do
    third = create_page(title: "Third")
    open_tree
    set_timing("interval", 600)
    set_timing("chunk", 2)
    page.execute_script(<<~JS)
      window.__parts = []
      window.__open = 0
      window.__fetch = window.fetch
      window.fetch = async (...args) => {
        if (!String(args[0]).includes("/presence/here")) return window.__fetch(...args)
        const part = { ids: new URL(String(args[0]), location.href).searchParams.getAll("ids[]"), alone: window.__open === 0 }
        window.__parts.push(part)
        window.__open += 1
        try { return await window.__fetch(...args) } finally { window.__open -= 1 }
      }
    JS
    before = reads

    join(:dana, @dana)
    join(:reader, @reader, path: "/cs-studio/pages/#{third.id}")
    assert_selector shown(tree_marker), wait: LIVE
    assert_selector shown(tree_marker(third)), wait: LIVE
    await_read(before + 1)

    parts = page.evaluate_script("window.__parts")
    ids = Page.kept.pluck(:id).map(&:to_s)
    assert_operator ids.size, :>=, 4
    reading = parts.first((ids.size / 2.0).ceil)
    assert_equal ids.sort, reading.flat_map { |part| part["ids"] }.sort, "one reading did not ask about every marker exactly once"
    assert reading.all? { |part| part["ids"].size <= 2 }
    assert parts.all? { |part| part["alone"] }, "two parts were out at the same time"
  end

  # An answer that is an error leaves the markers as they are, and the next
  # tick asks again.
  test "a failed reading leaves the markers as they are, and the next one draws" do
    open_tree
    join(:dana, @dana)
    assert_selector shown(tree_marker), wait: LIVE
    page.execute_script(<<~JS)
      window.__failed = 0
      window.__fail = true
      window.__fetch = window.fetch
      window.fetch = (...args) => {
        if (!window.__fail || !String(args[0]).includes("/presence/here")) return window.__fetch(...args)
        window.__failed += 1
        return Promise.resolve(new Response("{}", { status: 500, headers: { "Content-Type": "application/json" } }))
      }
    JS
    set_timing("interval", 300)
    set_timing("refresh", 400)

    leave(:dana)
    await_js("window.__failed >= 2", wait: LIVE)
    assert_selector shown(tree_marker)
    assert_selector "#{tree_marker} [data-presence-marker-label]", text: "Dana Weiss is here", exact_text: true, visible: :all

    page.execute_script("window.__fail = false")
    assert_selector "#{tree_marker}[hidden]", visible: :all, wait: LIVE
  end

  # An older answer never overwrites a newer one: a reading that is still
  # out when the next begins is ended, and what it brings later is dropped.
  test "an answer that arrives after a newer one was drawn changes nothing" do
    open_tree
    set_timing("interval", 300)
    page.execute_script(<<~JS)
      window.__held = null
      window.__hold = true
      window.__fetch = window.fetch
      window.fetch = (...args) => {
        if (!window.__hold || !String(args[0]).includes("/presence/here")) return window.__fetch(...args)
        window.__hold = false
        // The first reading from now on is kept back, and will answer
        // "nobody anywhere" whatever is true by then; it does not honour the abort.
        return new Promise((resolve) => { window.__held = () => resolve(new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } })) })
      }
    JS
    before = reads

    signal
    await_js("window.__held !== null", wait: LIVE)
    join(:dana, @dana)
    assert_selector shown(tree_marker), wait: LIVE
    drawn = reads
    assert_operator drawn, :>, before

    page.execute_script("window.__held()")
    await_frames
    await_frames
    assert_selector shown(tree_marker)
    assert_equal drawn, reads
  end
end
