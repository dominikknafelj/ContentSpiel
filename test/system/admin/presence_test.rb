require "application_system_test_case"

# Presence where a person sees it (presence spec §5.1, the handoff's items 1
# to 8 and 13 to 17): the others on a record, in an editor's header and in
# the media library's image panel, live. Two people are two Capybara
# sessions. `await_notes_live` waits for presence's subscription too
# (`live/state`), so an arrival caused after it is heard.
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

  # The group: one button, the header's one Tab stop for presence.
  def group = ".admin-editor-header .admin-presence button"

  def list = ".admin-editor-header .admin-presence [role=list]"

  def circle(user, state = nil) = "#{group} > [data-presence-user='#{user.id}']#{"[data-presence-state=#{state}]" if state}"

  def tip(user) = "#{circle(user)} [data-tooltip]"

  # The part's own reading has been drawn: what is shown is no longer the
  # server's first rendering, and the next drawing is a change.
  def await_drawn(within: ".admin-editor-header")
    await_js("document.querySelector(#{"#{within} [data-controller~='admin--presence--record']".to_json})?.dataset.presenceDrawn === 'true'", wait: LIVE)
  end

  def turbo_visit(path)
    page.execute_script("window.__visited = false; document.addEventListener('turbo:load', () => { window.__visited = true }, { once: true }); Turbo.visit(#{path.to_json})")
    await_js("window.__visited === true", wait: LIVE)
  end

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
    assert_no_selector group

    join(:dana, @dana) do
      assert_selector circle(@me, "here"), wait: LIVE
      assert_selector "#{group}[aria-label='Also open by 1 person: Olga Braun, here']"
      assert_no_selector "[data-presence-user='#{@dana.id}']"
    end

    assert_selector circle(@dana, "here"), wait: LIVE
    assert_selector "#{group}[aria-label='Also open by 1 person: Dana Weiss, here']"
    assert_no_selector "[data-presence-user='#{@me.id}']"
    # The circle: 24px, the initials, first in the action row and 12px before
    # the status that follows (handoff 1 and 2).
    assert_selector circle(@dana) + " > span.size-6[aria-hidden=true]", text: "DW", exact_text: true
    box = page.evaluate_script(<<~JS)
      (() => {
        const people = document.querySelector(".admin-editor-header [data-controller~='admin--presence--record']")
        const circle = people.querySelector("[data-presence-user] > span").getBoundingClientRect()
        return { first: people.parentElement.firstElementChild === people, width: circle.width, height: circle.height, row: people.getBoundingClientRect().height,
                 gap: people.nextElementSibling.getBoundingClientRect().left - people.getBoundingClientRect().right }
      })()
    JS
    assert_equal({ "first" => true, "width" => 24, "height" => 24, "row" => 24, "gap" => 12 }, box)
    assert_no_selector ".admin-editor-header .admin-presence [title]", visible: :all
  end

  # Handoff 23: the whole group is ONE Tab stop, a button that says who is
  # there and opens the list of everyone; the list takes the focus and
  # Escape gives it back.
  test "the group is one Tab stop: its name says who is there, Enter opens the list and moves the focus into it, and Escape gives the focus back" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana), wait: LIVE
    await_drawn

    stops = page.evaluate_script("[ ...document.querySelectorAll('.admin-editor-header .admin-presence :is(a, button, input, [tabindex])') ].filter((each) => each.tabIndex >= 0).length")
    assert_equal 1, stops
    # Handoff 28: the focus alone opens nothing, and neither does the pointer
    # on the group (the list would cover the header); the group says by its
    # cursor that it is pressed, and its focus ring is CS Studio's 2px corner
    # (31), not a pill.
    page.execute_script("document.querySelector(#{group.to_json}).focus()")
    find(circle(@dana)).hover
    await_frames
    assert_no_selector list
    assert_selector "#{group}[aria-expanded=false]"
    assert_equal true, page.evaluate_script("document.activeElement === document.querySelector(#{group.to_json})")
    look = page.evaluate_script("(() => { const style = getComputedStyle(document.querySelector(#{group.to_json})); return [ style.cursor, style.borderTopLeftRadius ] })()")
    assert_equal [ "pointer", "2px" ], look
    page.driver.browser.mouse.move(x: 5, y: 5)
    find(group).send_keys(:enter)
    assert_selector "#{list}[aria-label='Everyone with this open'] [role=listitem]", count: 1
    assert_selector "#{group}[aria-expanded=true]"
    assert_eventually(message: "the list did not take the focus") { page.evaluate_script("document.activeElement === document.querySelector(#{list.to_json})") }
    assert_equal [ [ "Dana Weiss", "here" ] ], all("#{list} [data-presence-listed]").map { |row| [ row.find("[data-presence-name]").text, row.find("[data-presence-status]").text ] }

    find(list).send_keys(:escape)
    assert_no_selector list
    assert_selector "#{group}[aria-expanded=false]"
    assert_equal true, page.evaluate_script("document.activeElement === document.querySelector(#{group.to_json})")

    # A press anywhere on the group opens it too, a circle included; a second
    # press closes it; and it closes when the focus leaves it.
    find(circle(@dana)).click
    assert_selector "#{list} [role=listitem]", count: 1
    find(circle(@dana)).click
    assert_no_selector list
    find(group).click
    assert_selector list
    page.execute_script("document.activeElement.blur()")
    page.driver.browser.mouse.move(x: 5, y: 5)
    find(".admin-editor-header h1").click
    assert_no_selector list
  end

  test "they turn away when their tab is hidden, and here again when it is shown" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana, "here"), wait: LIVE

    using_session(:dana) { hide_document }
    # At once, and the unfilled circle (4): no fade marks a change of state.
    assert_selector circle(@dana, "away"), wait: LIVE
    assert_selector "#{group}[aria-label='Also open by 1 person: Dana Weiss, away just now']"
    assert_selector tip(@dana), text: "Dana Weiss · away just now", exact_text: true, visible: :all
    assert_selector circle(@dana) + " > span.bg-paper.border-line.text-meta"

    using_session(:dana) { show_document }
    assert_selector circle(@dana, "here"), wait: LIVE
    assert_selector "#{group}[aria-label='Also open by 1 person: Dana Weiss, here']"
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
    assert_no_selector group
    assert_eventually(message: "the row of a tab that left stayed") { marks(@dana).none? }
  end

  test "the same person in two sessions is one circle, and they never see themselves" do
    open_page
    join(:dana, @dana)
    join(:dana_again, @dana) { assert_selector circle(@me), wait: LIVE }
    assert_eventually(message: "the second tab wrote no row of its own") { marks(@dana).count == 2 }

    assert_selector circle(@dana), count: 1, wait: LIVE
    assert_selector "#{group}[aria-label='Also open by 1 person: Dana Weiss, here']"
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
    sleep 1 # sleep: the arrival's signal is held for half a second and the shortened slow timer runs every 200 ms; "fetched nothing" needs both to have had their turn
    assert_eventually(message: "the hidden tab never reported away") { marks(@me).where(state: "away").exists? }
    assert_no_selector circle(@dana)

    show_document
    assert_selector circle(@dana, "here"), wait: LIVE
  end

  test "a viewer with read-only rights is shown like anyone else" do
    open_page
    join(:reader, @reader) { assert_selector circle(@me, "here"), wait: LIVE }

    assert_selector circle(@reader, "here"), wait: LIVE
    assert_selector "#{group}[aria-label='Also open by 1 person: reader, here']"
    assert_selector circle(@reader) + " > span.bg-sunken", text: "R", exact_text: true
  end

  # Handoff 14 and 25: arriving fades in; leaving does not fade.
  test "someone arriving fades in beside those who were there, and someone leaving is simply gone" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana) + "[data-presence-arriving]", wait: LIVE
    assert_equal [ "admin-presence-in", "0.15s" ],
      page.evaluate_script("(({ animationName, animationDuration }) => [ animationName, animationDuration ])(getComputedStyle(document.querySelector(#{circle(@dana).to_json})))")

    # Whoever is there when the page is opened did not arrive: the viewer did.
    open_page
    assert_selector circle(@dana), wait: LIVE
    await_drawn
    assert_no_selector "[data-presence-arriving]"
    page.execute_script(<<~JS)
      window.__faded = []
      new MutationObserver((changes) => changes.forEach((change) => {
        if (change.type === "attributes") window.__faded.push(`${change.attributeName}:${change.target.dataset.presenceUser}`)
      })).observe(document.querySelector(".admin-editor-header turbo-frame"), { attributes: true, subtree: true, attributeFilter: [ "data-presence-leaving", "style", "class" ] })
    JS

    join(:reader, @reader)
    assert_selector circle(@reader) + "[data-presence-arriving]", wait: LIVE
    assert_no_selector circle(@dana) + "[data-presence-arriving]"

    using_session(:dana) { visit admin_tags_path }
    assert_no_selector circle(@dana), wait: LIVE
    assert_equal [], page.evaluate_script("window.__faded"), "someone leaving was marked or restyled before going"
    assert_selector circle(@reader), count: 1
    assert_no_selector "[data-presence-arriving]"
  end

  # The read once a minute that finds nothing new must touch nothing: every
  # drawing replaces the group, and a screen reader would be told it again.
  test "an answer that is the one shown is not drawn again, and the focus stays on the very button it was on" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana), wait: LIVE
    await_drawn
    page.execute_script("window.__button = document.querySelector(#{group.to_json}); window.__button.focus()")

    set_timing("refresh", 150)
    # Several of the shortened reads have been answered by the time a second
    # has passed.
    await_js("performance.getEntriesByType('resource').filter((each) => each.name.includes('/presence/page/')).length >= 4", wait: LIVE)
    assert_equal [ true, true ], page.evaluate_script("[ window.__button.isConnected, document.activeElement === window.__button ]")

    # A change is drawn, and the focus is on the new group's button.
    using_session(:dana) { hide_document }
    assert_selector circle(@dana, "away"), wait: LIVE
    assert_equal [ false, true ], page.evaluate_script("[ window.__button.isConnected, document.activeElement === document.querySelector(#{group.to_json}) ]")

    # The one person leaves: nothing is left to hold the focus.
    using_session(:dana) { visit admin_tags_path }
    assert_no_selector group, wait: LIVE
    assert_equal true, page.evaluate_script("document.activeElement === document.body")
  end

  # The re-review's M1: "away 12 min" is in the answer three times and grows
  # about once a refresh, so with an away person on screen nearly every read
  # differs from the one shown. Only its texts do: they are changed where
  # they stand, and nothing is replaced under whoever is reading.
  def away_since(minutes)
    Presence::Mark.where(user_id: @dana.id).update_all(state_at: minutes.minutes.ago - 5.seconds) # version: none (a test of presence)
  end

  test "an away person's growing minutes change the texts in place: the same button keeps the focus, an open list stays read, a showing tooltip stays shown" do
    open_page
    join(:dana, @dana) { hide_document }
    assert_selector circle(@dana, "away"), wait: LIVE
    await_drawn
    assert_selector "#{group}[aria-label='Also open by 1 person: Dana Weiss, away just now']", wait: LIVE
    page.execute_script("window.__button = document.querySelector(#{group.to_json}); window.__circle = document.querySelector(#{circle(@dana).to_json}); window.__button.focus()")
    set_timing("refresh", 150)

    # The focus on the group's button.
    away_since(12)
    assert_selector "#{group}[aria-label='Also open by 1 person: Dana Weiss, away 12 min']", wait: LIVE
    assert_equal [ true, true, true ], page.evaluate_script("[ window.__button === document.querySelector(#{group.to_json}), window.__circle.isConnected, document.activeElement === window.__button ]")

    # The list open and being read.
    find(group).send_keys(:enter)
    assert_eventually(message: "the list did not take the focus") { page.evaluate_script("document.activeElement === document.querySelector(#{list.to_json})") }
    page.execute_script("window.__list = document.querySelector(#{list.to_json})")
    away_since(13)
    assert_selector "#{list} [data-presence-listed='#{@dana.id}'] [data-presence-status]", text: "away 13 min", exact_text: true, wait: LIVE
    assert_equal [ true, true, true ], page.evaluate_script("[ window.__list === document.querySelector(#{list.to_json}), document.activeElement === window.__list, window.__button.isConnected ]")
    assert_selector "#{group}[aria-expanded=true]"
    find(list).send_keys(:escape)
    assert_no_selector list

    # A tooltip that is showing.
    find(circle(@dana)).hover
    assert_selector tip(@dana), text: "Dana Weiss · away 13 min", exact_text: true
    page.execute_script("window.__tip = document.querySelector(#{tip(@dana).to_json})")
    away_since(14)
    assert_selector tip(@dana), text: "Dana Weiss · away 14 min", exact_text: true, wait: LIVE
    assert_equal true, page.evaluate_script("window.__tip === document.querySelector(#{tip(@dana).to_json}) && !window.__tip.hidden")

    # A real change is still drawn anew: she is back.
    using_session(:dana) { show_document }
    assert_selector circle(@dana, "here"), wait: LIVE
    assert_equal false, page.evaluate_script("window.__button.isConnected")
  end

  # The review's first finding: someone behind "+N" has no circle, so the
  # comparison that decides "only the words differ" has to look at the rows
  # too -- how each person is, and their initials. Four others, written as
  # rows (no browsers needed): the fourth is behind "+1".
  test "someone behind +N who turns away, or is renamed, is drawn anew: their row shows it" do
    open_page
    now = Time.current
    others = Array.new(4) { |i| User.create!(name: "Person #{i}", email_address: "person#{i}@example.com", password: "a-long-password-1") }
    others.each_with_index do |user, index|
      Presence::Mark.insert!({ user_id: user.id, record_type: "Page", record_id: @page.id, tab: "tab-#{user.id}-1234567", token: SecureRandom.hex(8), state: "here", seen_at: now, arrived_at: now - (20 - index).minutes, state_at: now - (20 - index).minutes }) # version: none (a test of presence)
    end
    hidden = others.last
    row = "#{list} [data-presence-listed='#{hidden.id}']"
    set_timing("refresh", 150)
    assert_selector "#{group} [data-presence-more=wide]", text: "+1", exact_text: true, wait: LIVE
    assert_no_selector circle(hidden), visible: :all
    assert_selector "#{row}[data-presence-state=here] > span.bg-sunken", text: "P3", exact_text: true, visible: :all

    Presence::Mark.where(user_id: hidden.id).update_all(state: "away", state_at: Time.current, seen_at: Time.current) # version: none (a test of presence)
    assert_selector "#{row}[data-presence-state=away] [data-presence-status]", text: "away just now", exact_text: true, visible: :all, wait: LIVE
    # The away look, not only the away words.
    assert_selector "#{row} > span.bg-paper.text-meta", text: "P3", exact_text: true, visible: :all
    assert_no_selector "#{row} > span.bg-sunken", visible: :all

    hidden.update!(name: "Zed Young")
    assert_selector "#{row} [data-presence-name]", text: "Zed Young", exact_text: true, visible: :all, wait: LIVE
    assert_selector "#{row} > span.bg-paper", text: "ZY", exact_text: true, visible: :all, wait: LIVE
  end

  # A drawing replaces the group, and with it the element that knew the list
  # had been entered: the list someone reads is open and read again in the
  # new one, and the next press of the button closes it (the re-review's
  # second item; the `reading` branch of the script's `put`).
  test "a list being read survives a real redraw, and the next press of the button closes it" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana), wait: LIVE
    await_drawn
    page.execute_script("document.querySelector(#{group.to_json}).focus()")
    find(group).send_keys(:enter)
    assert_eventually(message: "the list did not take the focus") { page.evaluate_script("document.activeElement === document.querySelector(#{list.to_json})") }
    page.execute_script("window.__list = document.querySelector(#{list.to_json})")

    join(:reader, @reader)
    assert_selector "#{list} [role=listitem]", count: 2, wait: LIVE
    assert_equal [ false, true ], page.evaluate_script("[ window.__list.isConnected, document.activeElement === document.querySelector(#{list.to_json}) ]")
    assert_selector "#{group}[aria-expanded=true]"

    find(group).click
    assert_no_selector list
    assert_selector "#{group}[aria-expanded=false]"
    assert_equal true, page.evaluate_script("document.activeElement === document.querySelector(#{group.to_json})")
  end

  # Two small things about the list and the pointer (the re-review's third
  # item), at a width where the header shows "+N".
  test "a list shown by hovering +N closes when the pointer leaves even with the focus on the button, and no tooltip shows over an open list" do
    original = page.current_window.size
    page.current_window.resize_to(900, 900)
    open_page
    join(:dana, @dana)
    join(:reader, @reader)
    assert_selector "#{group} [data-presence-more=narrow]", text: "+1", exact_text: true, wait: LIVE
    await_drawn

    # Opened and closed by a press: the focus is on the button now.
    find(group).click
    assert_selector list
    find(group).click
    assert_no_selector list
    assert_equal true, page.evaluate_script("document.activeElement === document.querySelector(#{group.to_json})")
    find(".admin-editor-header h1").hover

    find("#{group} [data-presence-more=narrow]").hover
    assert_selector "#{list} [role=listitem]", count: 2
    # The pointer on a circle, under the open list: its tooltip would lie
    # over the list.
    find(circle(@dana)).hover
    sleep 0.6 # sleep: twice the tooltip's 300ms wait, to see that none shows while the list is open
    assert_no_selector tip(@dana)
    assert_selector list
    find(".admin-editor-header h1").hover
    assert_no_selector list
    assert_selector "#{group}[aria-expanded=false]"
    # With the list closed the tooltip is back.
    find(circle(@dana)).hover
    assert_selector tip(@dana)
  ensure
    page.current_window.resize_to(*original)
  end

  test "the media panel shows who has the image open, between the name and the close, and nobody once they close it" do
    asset = create_media_asset
    asset.update_columns(title: "a-very-long-file-name-that-would-have-wrapped-over-several-lines-of-the-panel.png") # version: none (a system test's own image)
    visit "/cs-studio/media?selected=#{asset.id}"
    await_notes_live
    assert_selector "#media-panel turbo-frame#presence-media-#{asset.id}", visible: :all
    assert_no_selector "#media-panel .admin-presence button"
    alone = page.evaluate_script("document.querySelector('#media-panel a[aria-label=\"Close panel\"]').getBoundingClientRect().left - document.querySelector('#media-panel-title').getBoundingClientRect().right")
    assert_equal 12, alone, "with nobody else the close is not 12px after the name"

    join(:dana, @dana, path: "/cs-studio/media?selected=#{asset.id}") { assert_selector "#media-panel [data-presence-user='#{@me.id}']", wait: LIVE }

    assert_selector "#media-panel .admin-presence button[aria-label='Also open by 1 person: Dana Weiss, here'] > [data-presence-user='#{@dana.id}']", wait: LIVE
    row = page.evaluate_script(<<~JS)
      (() => {
        const box = (selector) => document.querySelector(`#media-panel ${selector}`).getBoundingClientRect()
        const [ name, people, circle, close ] = [ box("#media-panel-title"), box("[data-controller~='admin--presence--record']"), box("[data-presence-user] > span"), box("a[aria-label='Close panel']") ]
        const title = document.querySelector("#media-panel-title")
        const ring = getComputedStyle(document.querySelector("#media-panel [data-presence-user] > span")).boxShadow
        const surface = getComputedStyle(document.querySelector("#media-panel").parentElement.closest(".bg-surface")).backgroundColor
        return { circle: circle.width, afterName: people.left - name.right, beforeClose: close.left - people.right, cut: title.scrollWidth > title.clientWidth,
                 oneLine: name.height, centred: (circle.top + circle.height / 2) - (name.top + name.height / 2), closeLast: close.right > people.right,
                 whole: title.firstElementChild.title, ringOnSurface: ring.includes(surface) }
      })()
    JS
    # 20px circles, centred on the name's one line of 28px (handoff 24).
    assert_equal({ "circle" => 20, "afterName" => 8, "beforeClose" => 12, "cut" => true, "oneLine" => 28, "centred" => 0, "closeLast" => true, "whole" => asset.title, "ringOnSurface" => true }, row)

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
    assert_selector "#{group} > [data-presence-user]", count: 2
    assert_no_selector "#{group} [data-presence-more]"

    page.current_window.resize_to(900, 900)
    assert_selector "#{group} > [data-presence-user]", count: 1
    assert_selector circle(@dana)
    assert_selector "#{group} [data-presence-more=narrow]", text: "+1", exact_text: true
    more = page.evaluate_script(<<~JS)
      (() => {
        const group = document.querySelector(#{group.to_json})
        const [ circle, count ] = [ group.querySelector("[data-presence-user] > span"), group.querySelector("[data-presence-more]").parentElement ]
        const [ a, b ] = [ circle.getBoundingClientRect(), count.getBoundingClientRect() ]
        const paper = getComputedStyle(document.querySelector(".admin-editor-header")).backgroundColor
        return { width: b.width, height: b.height, after: b.left - a.right, unfilled: getComputedStyle(count).backgroundColor === paper }
      })()
    JS
    # A circle of the same size with no fill, 4px after the last person (20).
    assert_equal({ "width" => 24, "height" => 24, "after" => 4, "unfilled" => true }, more)

    # Hovering "+N" shows the list of everyone, in the same order (6), and
    # leaves the focus where it was; a redraw under the open list leaves it
    # open; it goes when the pointer does.
    find("#{group} [data-presence-more=narrow]").hover
    assert_selector "#{list} [role=listitem]", count: 2
    assert_equal true, page.evaluate_script("document.activeElement === document.body")
    assert_equal [ [ "Dana Weiss", "here" ], [ "reader", "here" ] ],
      all("#{list} [data-presence-listed]").map { |row| [ row.find("[data-presence-name]").text, row.find("[data-presence-status]").text ] }
    using_session(:dana) { hide_document }
    assert_selector "#{list} [data-presence-listed='#{@dana.id}'] [data-presence-status]", text: "away just now", wait: LIVE
    assert_selector "#{group}[aria-expanded=true]"
    # Here before away: the reader is the one circle now.
    assert_selector circle(@reader)
    find(".admin-editor-header h1").hover
    assert_no_selector list
    assert_selector "#{group}[aria-expanded=false]"

    # Below 1024px the notes are a sheet over the editor (15): the people are
    # not shown, and not there for a keyboard or a screen reader either.
    find("#notes-open").click
    assert_selector "#notes-drawer #notes-list"
    assert_no_selector ".admin-editor-header .admin-presence"
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.admin-editor-header .admin-presence')).display")
    # Closed again, they are back.
    within("#notes-drawer") { find("button", text: /Back to/).click }
    assert_selector circle(@reader)
  ensure
    page.current_window.resize_to(*original)
  end

  # --- the tooltip (handoff 18), on the circles that are its first hosts ----

  # When the bubble of `user`'s circle was shown, after the pointer came.
  def watch_tooltips
    page.execute_script(<<~JS)
      window.__tips = {}
      document.querySelectorAll(".admin-presence [data-presence-user]").forEach((host) => {
        const id = host.dataset.presenceUser
        window.__tips[id] = {}
        host.addEventListener("mouseenter", () => { window.__tips[id].entered = performance.now() })
        new MutationObserver(() => { if (!host.querySelector("[data-tooltip]").hidden) window.__tips[id].shown = performance.now() })
          .observe(host.querySelector("[data-tooltip]"), { attributes: true, attributeFilter: [ "hidden" ] })
      })
    JS
  end

  def waited(user) = page.evaluate_script("window.__tips[#{user.id}].shown - window.__tips[#{user.id}].entered")

  test "a circle's tooltip: after 300ms on hover, 6px under the circle and centred, at once from one circle to the next, and gone on Escape or a press" do
    open_page
    join(:dana, @dana)
    join(:reader, @reader)
    assert_selector "#{group} > [data-presence-user]", count: 2, wait: LIVE
    await_js("document.querySelector(#{".admin-editor-header [data-controller~='admin--presence--record']".to_json}).querySelectorAll('[data-controller=\"admin--ui--tooltip\"]').length === 2")
    await_admin_controllers
    assert_no_selector tip(@dana)
    watch_tooltips

    find(circle(@dana)).hover
    assert_selector tip(@dana), text: "Dana Weiss · here", exact_text: true
    assert_operator waited(@dana), :>=, 290
    look = page.evaluate_script(<<~JS)
      (() => {
        const host = document.querySelector(#{circle(@dana).to_json})
        const [ a, b ] = [ host.getBoundingClientRect(), host.querySelector("[data-tooltip]").getBoundingClientRect() ]
        const style = getComputedStyle(host.querySelector("[data-tooltip]"))
        const header = getComputedStyle(document.querySelector(".admin-editor-header h1"))
        return { below: Math.round(b.top - a.bottom), centred: Math.abs((b.left + b.width / 2) - (a.left + a.width / 2)) <= 0.5, size: style.fontSize, shadow: style.boxShadow,
                 inverted: style.backgroundColor === header.color, padding: [ style.paddingTop, style.paddingLeft ], narrow: b.width <= 240 }
      })()
    JS
    assert_equal({ "below" => 6, "centred" => true, "size" => "12px", "shadow" => "none", "inverted" => true, "padding" => %w[4px 8px], "narrow" => true }, look)

    # To the next circle: at once, and one bubble at a time.
    find(circle(@reader)).hover
    assert_selector tip(@reader), text: "reader · here", exact_text: true
    assert_operator waited(@reader), :<, 150
    assert_no_selector tip(@dana)

    # Escape: gone, and the focus where it was.
    page.execute_script("document.querySelector(#{group.to_json}).focus()")
    find(group).send_keys(:escape)
    assert_no_selector tip(@reader)
    assert_equal true, page.evaluate_script("document.activeElement === document.querySelector(#{group.to_json})")
    assert_no_selector list

    # A press on the circle: no bubble over the list it opens, and none until
    # the pointer has left and come back.
    find(".admin-editor-header h1").hover
    find(circle(@dana)).hover
    assert_selector tip(@dana)
    find(circle(@dana)).click
    assert_selector list
    assert_no_selector tip(@dana)
    sleep 0.6 # sleep: the tooltip's own wait is 300 ms; "it does not come back" needs that to have passed twice
    assert_no_selector tip(@dana)
    find(list).send_keys(:escape)
    find(".admin-editor-header h1").hover
    find(circle(@dana)).hover
    assert_selector tip(@dana)
    find(".admin-editor-header h1").hover
    assert_no_selector tip(@dana)
  end

  test "a tooltip that would leave the box it is in lines up with its host's edge on that side" do
    @dana.update!(name: "Dana Weiss-Hohenlohe of the Long Name")
    asset = create_media_asset
    visit "/cs-studio/media?selected=#{asset.id}"
    await_notes_live
    join(:dana, @dana, path: "/cs-studio/media?selected=#{asset.id}")
    host = "#media-panel .admin-presence [data-presence-user='#{@dana.id}']"
    assert_selector host, wait: LIVE
    await_drawn(within: "#media-panel")
    await_admin_controllers

    find(host).hover
    assert_selector "#{host} [data-tooltip][data-align=right]", text: "Dana Weiss-Hohenlohe of the Long Name · here"
    edges = page.evaluate_script(<<~JS)
      (() => {
        const host = document.querySelector(#{host.to_json})
        const [ a, b ] = [ host.getBoundingClientRect(), host.querySelector("[data-tooltip]").getBoundingClientRect() ]
        const panel = document.querySelector("#media-panel").parentElement.getBoundingClientRect()
        return { lined: Math.abs(b.right - a.right) <= 0.5, inside: b.left >= panel.left && b.right <= panel.right, below: Math.round(b.top - a.bottom), wide: b.width <= 240 }
      })()
    JS
    assert_equal({ "lined" => true, "inside" => true, "below" => 6, "wide" => true }, edges)
  end

  # The circles take no focus, so the keyboard's half of the tooltip is shown
  # on a host made for the test: a copy of the first circle with a tab index,
  # put after the group (inside a button nothing is a Tab stop).
  test "a tooltip's host that takes the focus shows it at once for the keyboard, and Escape hides it with the focus still there" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana), wait: LIVE
    await_drawn
    page.execute_script(<<~JS)
      const host = document.querySelector(#{circle(@dana).to_json}).cloneNode(true)
      host.id = "focus-host"
      host.tabIndex = 0
      host.removeAttribute("data-presence-user")
      document.querySelector(".admin-editor-header .admin-presence").append(host)
      window.__shown = null
      new MutationObserver(() => { if (!host.querySelector("[data-tooltip]").hidden) window.__shown = performance.now() })
        .observe(host.querySelector("[data-tooltip]"), { attributes: true, attributeFilter: [ "hidden" ] })
    JS
    await_admin_controllers
    assert_no_selector "#focus-host [data-tooltip]"

    # By the keyboard: Tab from the group's button lands on it.
    page.execute_script("document.querySelector(#{group.to_json}).focus(); window.__at = performance.now()")
    find(group).send_keys(:tab)
    assert_selector "#focus-host [data-tooltip]", text: "Dana Weiss · here", exact_text: true
    assert_equal true, page.evaluate_script("document.activeElement.id === 'focus-host'")
    assert_operator page.evaluate_script("window.__shown - window.__at"), :<, 250, "the keyboard waited for its tooltip as the pointer does"
    find("#focus-host").send_keys(:escape)
    assert_no_selector "#focus-host [data-tooltip]"
    assert_equal true, page.evaluate_script("document.activeElement.id === 'focus-host'")

    # Away and back: shown again; and it goes with the focus.
    find("#focus-host").send_keys([ :shift, :tab ])
    find(group).send_keys(:tab)
    assert_selector "#focus-host [data-tooltip]"
    find("#focus-host").send_keys([ :shift, :tab ])
    assert_no_selector "#focus-host [data-tooltip]"
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
    # The positive control for the empty list above: the same collector
    # hears a real Turbo request and visit (a made-up event would not do:
    # Turbo's own listeners read its detail).
    assert_writes_settled
    page.execute_script("window.__turbo = []")
    click_link "Tags"
    assert_selector "main h1", text: "Tags"
    heard = page.evaluate_script("window.__turbo")
    assert_includes heard, "turbo:before-fetch-request"
    assert_includes heard, "turbo:visit"
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
      import("live/state").then(({ report, settle }) => {
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
    assert_selector "#refused-part[data-live-part=answered][data-presence-gone=true]", visible: :all, wait: LIVE
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
    assert_selector "#{group} > [data-presence-user]", count: 2, wait: LIVE
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

  # --- going and coming back (the review's I2) ------------------------------

  # A page the browser keeps for its Back button, and brings back: `pagehide`
  # ends the subscription at once, `pageshow` takes it up again and says how
  # the tab is.
  test "a page that is hidden away by the browser leaves at once, and is back when it is shown again" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana, "here"), wait: LIVE
    token = marks(@dana).sole.token

    using_session(:dana) { page.execute_script("window.dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true }))") }
    assert_no_selector circle(@dana), wait: LIVE
    assert_eventually(message: "the row of a page that went stayed") { marks(@dana).none? }

    using_session(:dana) do
      page.execute_script("window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }))")
      await_notes_live
      assert_selector circle(@me, "here"), wait: LIVE
    end
    assert_selector circle(@dana, "here"), wait: LIVE
    assert_not_equal token, marks(@dana).sole.token
    assert_equal "here", marks(@dana).sole.state
  end

  # "Leave site?" answered with Stay: the page asked, nothing was unloaded,
  # and the person who stays is still there for everyone. It holds because
  # leaving is heard at `pagehide` and not at `beforeunload`.
  test "a leave that is asked about and not taken changes nothing: still subscribed, still shown" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana, "here"), wait: LIVE
    row = marks(@dana).sole.attributes.slice("id", "token", "state")

    using_session(:dana) do
      # The question itself, asked and answered with Stay: a `beforeunload`
      # that is cancelled, as the leave guard cancels one over unsaved work
      # (`autosave_unload_test.rb`: the browser's dialog cannot be driven).
      page.execute_script(<<~JS)
        window.__asked = []
        for (let turn = 0; turn < 3; turn++) {
          const event = new Event("beforeunload", { cancelable: true })
          event.preventDefault()
          window.dispatchEvent(event)
          window.__asked.push(event.defaultPrevented)
        }
      JS
      assert_equal [ true, true, true ], page.evaluate_script("window.__asked")
      await_frames
      assert_equal "connected", page.evaluate_script("document.body.dataset.notesLive")
      assert_selector circle(@me, "here")
    end

    await_frames
    assert_selector circle(@dana, "here")
    assert_equal row, marks(@dana).sole.attributes.slice("id", "token", "state")
  end

  # A Turbo visit to the same record's screen replaces the page, and the part
  # with it; the subscription is kept (let go a task later, asked for again
  # in between), so the server sees no leave and no arrival.
  test "a Turbo visit to the same record keeps the tab's row and makes nobody appear to leave" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana, "here"), wait: LIVE
    await_drawn
    row = marks(@dana).sole.attributes.slice("id", "token", "arrived_at")
    page.execute_script(<<~JS)
      window.__drawings = 0
      new MutationObserver(() => { window.__drawings += 1 }).observe(document.querySelector(".admin-editor-header turbo-frame"), { childList: true })
    JS

    using_session(:dana) do
      turbo_visit "/cs-studio/pages/#{@page.id}?locale=de"
      await_notes_live
      assert_selector circle(@me, "here"), wait: LIVE
      turbo_visit "/cs-studio/pages/#{@page.id}"
      await_notes_live
      assert_selector circle(@me, "here"), wait: LIVE
    end

    sleep 1 # sleep: a signal would be held for half a second before the frame is read; "not drawn again" needs that to have passed
    assert_equal row, marks(@dana).sole.attributes.slice("id", "token", "arrived_at")
    assert_equal "here", marks(@dana).sole.state
    assert_equal 0, page.evaluate_script("window.__drawings"), "the other person's frame was drawn again: someone seemed to leave or arrive"
    assert_selector circle(@dana, "here")
  end

  # --- a record that is gone for the viewer (the review's M2) ---------------

  test "when the record goes to the trash the part stops: nobody is shown, nothing is asked any more, and the tab has left" do
    open_page
    join(:dana, @dana)
    assert_selector circle(@dana, "here"), wait: LIVE
    using_session(:dana) { assert_selector circle(@me, "here"), wait: LIVE }
    set_timing("refresh", 150)

    @page.update_columns(trashed_at: Time.current) # version: none (a system test puts its own page in the trash, around the service, to see a 404)
    assert_selector ".admin-editor-header [data-controller~='admin--presence--record'][data-presence-gone=true][data-live-part=answered]", visible: :all, wait: LIVE
    assert_no_selector group
    assert_eventually(message: "the tab that can no longer read the record kept its row") { marks(@me).none? }

    # No more reads: the shortened timer would have asked several times.
    asked = page.evaluate_script("performance.getEntriesByType('resource').filter((each) => each.name.includes('/presence/page/')).length")
    sleep 1 # sleep: the shortened timer would have asked six times in a second; "asks no more" needs that time to pass
    assert_equal asked, page.evaluate_script("performance.getEntriesByType('resource').filter((each) => each.name.includes('/presence/page/')).length")
    assert_equal "connected", page.evaluate_script("document.body.dataset.notesLive")
  end

  # The other way a record is gone: the server refuses the subscription (a
  # record the viewer may not read, or one that is not there). A part for a
  # page that does not exist, put beside the real one.
  test "a refused subscription stops the part: nobody is shown, its timers are gone and it asks nothing" do
    open_page
    page.execute_script(<<~JS)
      const real = document.querySelector(".admin-editor-header [data-controller~='admin--presence--record']")
      const part = real.cloneNode(true)
      part.id = "refused"
      part.setAttribute("data-live-part", "waiting")
      part.setAttribute("data-admin--presence--record-id-value", "0")
      part.setAttribute("data-admin--presence--record-url-value", "/cs-studio/presence/page/0")
      part.setAttribute("data-admin--presence--record-refresh-value", "150")
      part.querySelector("turbo-frame").id = "presence-page-0"
      part.querySelector("turbo-frame").append(Object.assign(document.createElement("span"), { id: "stale-person", textContent: "someone" }))
      real.after(part)
    JS

    assert_selector "#refused[data-presence-gone=true][data-live-part=answered]", visible: :all, wait: LIVE
    assert_no_selector "#stale-person", visible: :all
    await_notes_live
    sleep 1 # sleep: the shortened timer would have asked six times in a second; "asks nothing" needs that time to pass
    assert_equal 0, page.evaluate_script("performance.getEntriesByType('resource').filter((each) => each.name.includes('/presence/page/0')).length")
    assert_equal 0, Presence::Mark.where(record_type: "Page", record_id: 0).count
    # The real part beside it is untouched.
    assert_selector ".admin-editor-header [data-controller~='admin--presence--record']:not(#refused)[data-live-part=answered]:not([data-presence-gone])", visible: :all
  end
end
