require "application_system_test_case"

# Presence where a person sees it (presence spec §5.1, the handoff's items 1
# to 8 and 13 to 17): the others on a record, in an editor's header and in
# the media library's image panel, live. Two people are two Capybara
# sessions. `await_notes_live` waits for presence's subscription too
# (`notes/live_state`), so an arrival caused after it is heard.
class Admin::PresenceSystemTest < ApplicationSystemTestCase
  LIVE = 8

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @me = users(:one).tap { |user| user.update!(name: "Olga Braun") }
    @dana = users(:two).tap { |user| user.update!(name: "Dana Weiss") }
    @reader = users(:reader)
    @page = create_page(title: "Pricing")
    sign_in_via_form(@me)
  end

  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  def open_page
    visit "/cs-studio/pages/#{@page.id}"
    await_notes_live
  end

  # Another person on the page, in a session of their own.
  def join(name, user, path: "/cs-studio/pages/#{@page.id}")
    using_session(name) do
      sign_in_via_form(user)
      visit path
      await_notes_live
      yield if block_given?
    end
  end

  def circle(user, state = nil) = ".admin-editor-header [role=group] > [data-presence-user='#{user.id}']#{"[data-presence-state=#{state}]" if state}"

  def marks(user) = Presence::Mark.where(user_id: user.id, record_type: "Page", record_id: @page.id)

  # The document as hidden (another tab in front), and seen again: what the
  # page reads, `document.hidden`, and the event that says it changed
  # (`notes_live_test.rb` does the same).
  def hide_document
    page.execute_script(<<~JS)
      window.__hidden = true
      Object.defineProperty(document, "hidden", { get: () => window.__hidden, configurable: true })
      Object.defineProperty(document, "visibilityState", { get: () => (window.__hidden ? "hidden" : "visible"), configurable: true })
      document.dispatchEvent(new Event("visibilitychange"))
    JS
  end

  def show_document = page.execute_script("window.__hidden = false; document.dispatchEvent(new Event('visibilitychange'))")

  # One of the script's timings, shortened on its element: a value's change
  # takes effect at once.
  def set_timing(name, milliseconds, within: ".admin-editor-header")
    page.execute_script("document.querySelector(#{"#{within} [data-controller~='admin--presence--record']".to_json}).setAttribute('data-admin--presence--record-#{name}-value', #{milliseconds})")
  end

  def live_state = page.evaluate_script("[ document.body.dataset.notesLive, document.body.getAttribute('data-notes-live-parts') ]")

  test "someone who opens the page I am on appears in my header, and I in theirs, and neither sees themselves" do
    open_page
    assert_selector ".admin-editor-header turbo-frame#presence-page-#{@page.id}", visible: :all
    assert_no_selector ".admin-editor-header [role=group]"

    join(:dana, @dana) do
      assert_selector circle(@me, "here") + "[aria-label='Olga Braun · here']", wait: LIVE
      assert_no_selector "[data-presence-user='#{@dana.id}']"
    end

    assert_selector circle(@dana, "here") + "[aria-label='Dana Weiss · here']", wait: LIVE
    assert_selector ".admin-editor-header [role=group][aria-label='Also open by 1 person']"
    assert_no_selector "[data-presence-user='#{@me.id}']"
    # The circle: 24px, the initials, first in the action row and 12px before
    # the status that follows (handoff 1 and 2).
    assert_selector circle(@dana) + " > span.size-6[aria-hidden=true]", text: "DW", exact_text: true
    box = page.evaluate_script(<<~JS)
      (() => {
        const people = document.querySelector(".admin-editor-header [data-controller~='admin--presence--record']")
        const circle = people.querySelector("[data-presence-user] > span").getBoundingClientRect()
        return { first: people.parentElement.firstElementChild === people, width: circle.width, height: circle.height,
                 gap: people.nextElementSibling.getBoundingClientRect().left - people.getBoundingClientRect().right }
      })()
    JS
    assert_equal({ "first" => true, "width" => 24, "height" => 24, "gap" => 12 }, box)

    # The shared tooltip says the same on focus (7): never a `title`.
    assert_no_selector circle(@dana) + " [data-tooltip]"
    page.execute_script("document.querySelector(#{circle(@dana).to_json}).focus()")
    assert_selector circle(@dana) + " [data-tooltip]", text: "Dana Weiss · here", exact_text: true
    assert_no_selector ".admin-editor-header [role=group] [title]", visible: :all
  end

  test "they turn away when their tab is hidden, and here again when it is shown" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana, "here"), wait: LIVE

    using_session(:dana) { hide_document }
    # At once, and the unfilled circle (4): no fade marks a change of state.
    assert_selector circle(@dana, "away") + "[aria-label='Dana Weiss · away 0 min']", wait: LIVE
    assert_selector circle(@dana) + " > span.bg-paper.border-line.text-meta"
    assert_no_selector "[data-presence-arriving], [data-presence-leaving]"

    using_session(:dana) { show_document }
    assert_selector circle(@dana, "here") + "[aria-label='Dana Weiss · here']", wait: LIVE
    assert_selector circle(@dana) + " > span.bg-sunken.border-line-strong.text-ink"
  end

  test "they turn away after the idle time, and here again at the next thing they do" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana, "here"), wait: LIVE

    using_session(:dana) { set_timing("idle", 200) }
    assert_selector circle(@dana, "away"), wait: LIVE

    using_session(:dana) do
      set_timing("idle", 300_000)
      # A press in the page: any of a key, a press, a pointer move or a scroll.
      find(".admin-editor-header h1").click
    end
    assert_selector circle(@dana, "here"), wait: LIVE
  end

  test "they disappear when they leave the page" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana), wait: LIVE

    using_session(:dana) do
      visit admin_tags_path
      await_notes_live
    end

    assert_no_selector circle(@dana), wait: LIVE
    assert_no_selector ".admin-editor-header [role=group]"
    assert_eventually(message: "the row of a tab that left stayed") { marks(@dana).none? }
  end

  test "the same person in two sessions is one circle, and they never see themselves" do
    open_page
    join(:dana, @dana)
    join(:dana_again, @dana) { assert_selector circle(@me), wait: LIVE }
    assert_eventually(message: "the second tab wrote no row of its own") { marks(@dana).count == 2 }

    assert_selector circle(@dana), count: 1, wait: LIVE
    assert_selector ".admin-editor-header [role=group][aria-label='Also open by 1 person']"
    %i[dana dana_again].each do |name|
      using_session(name) do
        assert_selector circle(@me), count: 1
        assert_no_selector "[data-presence-user='#{@dana.id}']"
      end
    end

    # One of their tabs away, the other here: here (17).
    using_session(:dana) { hide_document }
    assert_eventually(message: "the hidden tab never reported away") { marks(@dana).where(state: "away").count == 1 }
    using_session(:dana_again) { assert_no_selector "[data-presence-user='#{@dana.id}']" }
    assert_selector circle(@dana, "here"), count: 1

    using_session(:dana_again) { visit admin_tags_path }
    assert_selector circle(@dana, "away"), count: 1, wait: LIVE
  end

  # A crashed tab or a dropped network sends no leave and causes no signal:
  # the server stops counting the row, and this tab asks again on its own.
  test "a keep-alive that stops makes them disappear within the stale time, without any signal" do
    open_page
    join(:dana, @dana) { set_timing("beat", 3_600_000) }
    assert_selector circle(@dana), wait: LIVE

    set_timing("refresh", 300)
    marks(@dana).update_all(seen_at: (Presence::STALE_AFTER + 1.second).ago) # version: none (a test of presence)

    assert_no_selector circle(@dana), wait: LIVE
    assert_equal 1, marks(@dana).count, "the row was deleted: this is not the test of a stale one"
  end

  test "a hidden tab fetches nothing, and reads who is here when it is seen again" do
    open_page
    hide_document
    set_timing("refresh", 200)

    join(:dana, @dana)
    # The arrival's signal is coalesced for half a second; three of the
    # shortened slow timers have run by the time this is over as well.
    await_js("true", wait: 1)
    assert_eventually(message: "the hidden tab never reported away") { marks(@me).where(state: "away").exists? }
    assert_no_selector circle(@dana)

    show_document
    assert_selector circle(@dana, "here"), wait: LIVE
  end

  test "a viewer with read-only rights is shown like anyone else" do
    open_page
    join(:reader, @reader) { assert_selector circle(@me, "here"), wait: LIVE }

    assert_selector circle(@reader, "here") + "[aria-label='reader · here']", wait: LIVE
    assert_selector circle(@reader) + " > span.bg-sunken", text: "R", exact_text: true
  end

  test "someone arriving fades in beside those who were there, and someone leaving fades out before the rest move up" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana) + "[data-presence-arriving]", wait: LIVE
    assert_equal [ "admin-presence-in", "0.15s" ],
      page.evaluate_script("(({ animationName, animationDuration }) => [ animationName, animationDuration ])(getComputedStyle(document.querySelector(#{circle(@dana).to_json})))")

    # Whoever is there when the page is opened did not arrive: the viewer did.
    open_page
    assert_selector circle(@dana), wait: LIVE
    await_js("document.querySelector(#{".admin-editor-header [data-controller~='admin--presence--record']".to_json}).dataset.presenceDrawn === 'true'", wait: LIVE)
    assert_no_selector "[data-presence-arriving]"
    page.execute_script(<<~JS)
      window.__leaving = []
      new MutationObserver((changes) => changes.forEach((change) => {
        if (change.attributeName === "data-presence-leaving") window.__leaving.push(change.target.dataset.presenceUser)
      })).observe(document.querySelector(".admin-editor-header turbo-frame"), { attributes: true, subtree: true })
    JS

    join(:reader, @reader)
    assert_selector circle(@reader) + "[data-presence-arriving]", wait: LIVE
    assert_no_selector circle(@dana) + "[data-presence-arriving]"

    using_session(:dana) { visit admin_tags_path }
    assert_no_selector circle(@dana), wait: LIVE
    assert_equal [ @dana.id.to_s ], page.evaluate_script("window.__leaving")
    assert_selector circle(@reader), count: 1
    assert_no_selector "[data-presence-arriving], [data-presence-leaving]"
  end

  test "the media panel shows who has the image open, between the name and the close, and nobody once they close it" do
    asset = create_media_asset
    asset.update_columns(title: "a-very-long-file-name-that-would-have-wrapped-over-several-lines-of-the-panel.png") # version: none (a system test's own image)
    visit "/cs-studio/media?selected=#{asset.id}"
    await_notes_live
    assert_selector "#media-panel turbo-frame#presence-media-#{asset.id}", visible: :all
    assert_no_selector "#media-panel [role=group]"
    alone = page.evaluate_script("document.querySelector('#media-panel a[aria-label=\"Close panel\"]').getBoundingClientRect().left - document.querySelector('#media-panel-title').getBoundingClientRect().right")
    assert_equal 12, alone, "with nobody else the close is not 12px after the name"

    join(:dana, @dana, path: "/cs-studio/media?selected=#{asset.id}") { assert_selector "#media-panel [data-presence-user='#{@me.id}']", wait: LIVE }

    assert_selector "#media-panel [role=group][aria-label='Also open by 1 person'] > [data-presence-user='#{@dana.id}'][aria-label='Dana Weiss · here']", wait: LIVE
    row = page.evaluate_script(<<~JS)
      (() => {
        const box = (selector) => document.querySelector(`#media-panel ${selector}`).getBoundingClientRect()
        const [ name, people, circle, close ] = [ box("#media-panel-title"), box("[data-controller~='admin--presence--record']"), box("[data-presence-user] > span"), box("a[aria-label='Close panel']") ]
        const title = document.querySelector("#media-panel-title")
        return { circle: circle.width, afterName: people.left - name.right, beforeClose: close.left - people.right, cut: title.scrollWidth > title.clientWidth,
                 oneLine: name.height < 40, closeLast: close.right > people.right, whole: title.firstElementChild.title }
      })()
    JS
    assert_equal({ "circle" => 20, "afterName" => 8, "beforeClose" => 12, "cut" => true, "oneLine" => true, "closeLast" => true, "whole" => asset.title }, row)

    # Closing the panel takes its element out of the page: that is leaving.
    using_session(:dana) do
      click_frame_link { find("#media-panel a[aria-label='Close panel']").click }
      assert_no_selector "#media-panel"
    end
    assert_no_selector "#media-panel [data-presence-user]", wait: LIVE
    assert_eventually(message: "the row of a closed panel stayed") { Presence::Mark.where(user_id: @dana.id).none? }
  end

  test "at a narrow window the header shows one circle and the count, which lists everyone, and the notes sheet shows nobody" do
    original = page.current_window.size
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana), wait: LIVE
    join(:reader, @reader)
    assert_selector circle(@reader), wait: LIVE
    # Wide: both, and no "+N".
    assert_selector ".admin-editor-header [role=group] > [data-presence-user]", count: 2
    assert_no_selector ".admin-editor-header [role=group] button"

    page.current_window.resize_to(900, 900)
    assert_selector ".admin-editor-header [role=group] > [data-presence-user]", count: 1
    assert_selector circle(@dana)
    assert_selector ".admin-editor-header [role=group] button", text: "+1", exact_text: true
    more = page.evaluate_script(<<~JS)
      (() => {
        const [ circle, button ] = [ "[data-presence-user] > span", "button" ].map((selector) => document.querySelector(`.admin-editor-header [role=group] ${selector}`).getBoundingClientRect())
        return { width: button.width, height: button.height, overlapped: button.left < circle.right }
      })()
    JS
    assert_equal({ "width" => 24, "height" => 24, "overlapped" => false }, more)

    # "+N" opens the list of everyone, in the same order (6); a redraw under
    # the open list leaves it open; Escape closes it.
    find(".admin-editor-header [role=group] button").click
    assert_selector ".admin-editor-header [role=list] [role=listitem]", count: 2
    assert_equal [ [ "Dana Weiss", "here" ], [ "reader", "here" ] ],
      all(".admin-editor-header [role=list] [data-presence-listed]").map { |row| [ row.find("[data-presence-name]").text, row.find("[data-presence-status]").text ] }
    using_session(:dana) { hide_document }
    assert_selector ".admin-editor-header [role=list] [data-presence-listed='#{@dana.id}'] [data-presence-status]", text: "away 0 min", wait: LIVE
    assert_selector ".admin-editor-header [role=group] button[aria-expanded=true]"
    # Here before away: the reader is the one circle now.
    assert_selector circle(@reader)
    find(".admin-editor-header [role=group] button").send_keys(:escape)
    assert_no_selector ".admin-editor-header [role=list]"
    assert_selector ".admin-editor-header [role=group] button[aria-expanded=false]"
    # Focus opens it too, and it closes when neither the focus nor the
    # pointer is on it any more.
    page.driver.browser.mouse.move(x: 5, y: 5)
    page.execute_script("document.activeElement.blur()")
    assert_no_selector ".admin-editor-header [role=list]"
    page.execute_script("document.querySelector('.admin-editor-header [role=group] button').focus()")
    assert_selector ".admin-editor-header [role=list] [role=listitem]", count: 2
    page.execute_script("document.activeElement.blur()")
    assert_no_selector ".admin-editor-header [role=list]"

    # Below 1024px the notes are a sheet over the editor, its header too (15).
    find("#notes-open").click
    assert_selector "#notes-drawer #notes-list"
    covered = page.evaluate_script(<<~JS)
      (() => {
        const box = document.querySelector(".admin-editor-header [data-presence-user] > span").getBoundingClientRect()
        const top = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2)
        return Boolean(top && top.closest("#notes-drawer"))
      })()
    JS
    assert covered, "a person's circle shows through the notes sheet"
  ensure
    page.current_window.resize_to(*original)
  end

  # Presence is not content: nothing a save reads or sends is touched, no
  # Turbo request starts in the editor, and nothing of the record is written.
  test "presence touches nothing: the page's autosave base, its address and its updated_at are what they were" do
    open_page
    before = @page.reload.updated_at
    base = page.evaluate_script("document.querySelector('input[name=base_updated_at]').value")
    address = page.current_url
    page.execute_script(<<~JS)
      window.__turbo = []
      for (const name of [ "turbo:before-fetch-request", "turbo:before-visit", "turbo:visit", "turbo:frame-load", "turbo:before-frame-render", "turbo:before-stream-render" ]) {
        document.addEventListener(name, () => window.__turbo.push(name))
      }
    JS
    # One save of the page's own first, so that what is compared below is a
    # base an autosave has moved, and the listeners are known to hear one.
    fill_in "Title", with: "Pricing and more"
    assert_eventually(message: "the page's own edit was never saved") { @page.reload.title(locale: :en) == "Pricing and more" }
    assert_writes_settled
    typed = { updated_at: @page.reload.updated_at, base: page.evaluate_script("document.querySelector('input[name=base_updated_at]').value") }
    assert_operator typed[:updated_at], :>, before
    assert_not_equal base, typed[:base]
    assert_includes page.evaluate_script("window.__turbo"), "turbo:before-stream-render"
    page.execute_script("window.__turbo = []")
    version = PublicSite.content_version
    events = Audit::Event.count

    join(:dana, @dana)
    assert_selector circle(@dana, "here"), wait: LIVE
    using_session(:dana) { hide_document }
    assert_selector circle(@dana, "away"), wait: LIVE
    hide_document
    show_document
    using_session(:dana) { visit admin_tags_path }
    assert_no_selector circle(@dana), wait: LIVE

    assert_equal typed[:updated_at], @page.reload.updated_at
    assert_equal typed[:base], page.evaluate_script("document.querySelector('input[name=base_updated_at]').value")
    assert_equal version, PublicSite.content_version
    # Dana signed in, which is an event; presence wrote none.
    assert_equal [], Audit::Event.order(:id).offset(events).pluck(:action).reject { |action| action.start_with?("session.") }
    assert_equal address, page.current_url
    assert_equal [], page.evaluate_script("window.__turbo"), "presence started a Turbo request, a visit or a render in the editor"
    # And the editor still saves, on the base it had: no 409.
    fill_in "Title", with: "Pricing, still"
    assert_eventually(message: "the edit after presence's comings and goings was not saved") { @page.reload.title(locale: :en) == "Pricing, still" }
    assert_no_selector "#editor-notice *"
  end

  test "typing does not make the tab report: a key only notes the time, and a pointer move is looked at once a second" do
    open_page
    join(:dana, @dana)
    seen = marks(@me).sole.seen_at
    state_at = marks(@me).sole.state_at

    page.execute_script(<<~JS)
      window.__sent = []
      import("@hotwired/turbo-rails").then((turbo) => turbo.cable.getConsumer()).then((consumer) => {
        const send = consumer.send.bind(consumer)
        consumer.send = (data) => { window.__sent.push(data.command === "message" ? JSON.parse(data.data).action : data.command); return send(data) }
        window.__watching = true
      })
    JS
    await_js("window.__watching === true")
    fill_in "Title", with: "abcdefghij"
    mouse = page.driver.browser.mouse
    10.times { |step| mouse.move(x: 300 + step * 5, y: 300) }
    assert_writes_settled
    await_frames
    assert_equal [], page.evaluate_script("window.__sent"), "a key or a pointer move sent something on the cable"

    assert_equal [ seen, state_at ], marks(@me).sole.values_at(:seen_at, :state_at), "a key or a pointer move sent something to the channel"
  end

  # --- what `await_notes_live` waits for -----------------------------------

  test "a page without presence is live without it, and a page with it only once its subscription is answered" do
    visit admin_tags_path
    await_notes_live
    assert_equal %w[connected none], live_state

    open_page
    assert_equal %w[connected answered], live_state
    assert_selector ".admin-editor-header [data-controller~='admin--presence--record'][data-live-part=answered]", visible: :all

    # The record's presence subscription drops, and only it: the page is not
    # live, whatever the notes' two halves say; back, it is.
    drop = "import('@hotwired/turbo-rails').then((turbo) => turbo.cable.getConsumer()).then((consumer) => consumer.subscriptions.subscriptions.find((each) => each.identifier.includes('Presence::Channel')).%s())"
    page.execute_script(format(drop, "disconnected"))
    await_js("document.body.dataset.notesLive === 'connecting'", wait: LIVE)
    assert_equal %w[connecting waiting answered answered],
      page.evaluate_script("[ document.body.dataset.notesLive, document.body.getAttribute('data-notes-live-parts'), document.body.getAttribute('data-notes-live-person'), document.body.getAttribute('data-notes-live-records') ]")
    page.execute_script(format(drop, "connected"))
    await_notes_live
    assert_equal %w[connected answered], live_state
  end

  test "the server draws presence's part as waiting, so the page is not live before its script has connected; a refused subscription is an answer" do
    open_page

    # The module itself, on a body of its own: both halves answered and a
    # part as the server draws it.
    result = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("notes/live_state").then(({ report, settle }) => {
        const body = document.createElement("body")
        body.innerHTML = '<div data-live-part="waiting"></div>'
        const states = []
        const say = () => states.push(`${body.dataset.notesLive}/${body.getAttribute("data-notes-live-parts")}`)
        report(body, "person", true); report(body, "records", true); say()
        body.firstElementChild.setAttribute("data-live-part", "answered"); settle(body); say()
        body.firstElementChild.remove(); settle(body); say()
        body.innerHTML = '<div data-live-part="answered"></div><div data-live-part="waiting"></div>'; settle(body); say()
        done(states)
      })
    JS
    assert_equal %w[connecting/waiting connected/answered connected/none connecting/waiting], result
    # As the server rendered this page, before any script: waiting (asked
    # again with the session's cookie, by a `fetch` the page makes).
    rendered = page.evaluate_async_script("const done = arguments[arguments.length - 1]; fetch(location.href, { headers: { Accept: 'text/html' } }).then((response) => response.text()).then(done)")
    assert_match(/data-controller="admin--presence--record"[^>]*data-live-part="waiting"|data-live-part="waiting"[^>]*data-controller="admin--presence--record"/, rendered)

    # A second part for a record that is not there: refused, which is an
    # answer, and the page is live again.
    page.execute_script(<<~JS)
      const part = document.querySelector(".admin-editor-header [data-controller~='admin--presence--record']").cloneNode(true)
      part.setAttribute("data-admin--presence--record-id-value", "0")
      part.setAttribute("data-live-part", "waiting")
      part.querySelector("turbo-frame").id = "presence-page-0"
      part.id = "refused-part"
      document.querySelector(".admin-editor-header").append(part)
    JS
    assert_selector "#refused-part[data-live-part=answered]", visible: :all, wait: LIVE
    await_notes_live
    page.execute_script("document.querySelector('#refused-part').remove()")
    await_notes_live
    assert_equal %w[connected answered], live_state
  end

  # Turbo's snapshot keeps the page as it was left, people included; what
  # comes out of the cache (Back, a preview) has them taken out before it
  # reaches the page, and connecting reads who is here now.
  test "coming back to an editor from Turbo's cache shows nobody from then, and reads who is here now" do
    open_page
    join(:dana, @dana)
    join(:reader, @reader)
    assert_selector ".admin-editor-header [role=group] > [data-presence-user]", count: 2, wait: LIVE
    page.execute_script(<<~JS)
      window.__rendered = []
      document.addEventListener("turbo:render", () => window.__rendered.push(document.querySelectorAll(".admin-editor-header [data-presence-user]").length))
    JS

    within("#sidebar") { click_link "Tags" }
    assert_selector "h1", text: "Tags"
    await_notes_live
    using_session(:dana) { visit admin_tags_path }
    assert_eventually(message: "the row of a tab that left stayed") { marks(@dana).none? }

    page.go_back
    assert_selector ".admin-editor-header h1", text: "Pricing"
    await_notes_live
    assert_selector circle(@reader), wait: LIVE
    assert_no_selector circle(@dana)
    assert_equal [ 0 ], page.evaluate_script("window.__rendered").last(1), "the page came out of the cache with the people of the visit before"
    assert_eventually(message: "coming back did not arrive again") { marks(@me).exists? }
  end

  # Leaving a page hides its document on the way out. A report of "away"
  # sent then would race the socket's own close on the server, and a row
  # written after the leave would keep the person on the record for as long
  # as a row stays fresh.
  test "a tab that is closing reports nothing: no row is left behind" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana), wait: LIVE

    3.times do
      using_session(:dana) do
        visit admin_tags_path
        visit "/cs-studio/pages/#{@page.id}"
        await_notes_live
      end
    end
    using_session(:dana) { visit admin_tags_path }

    assert_eventually(message: "a closing tab left a row behind: #{marks(@dana).pluck(:state)}") { marks(@dana).none? }
    assert_no_selector circle(@dana), wait: LIVE
  end
end
