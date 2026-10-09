require "application_system_test_case"

# A mention's chime and desktop notification, and their two switches on the
# account screen (notes spec §6.4, D18, D19).
#
# Nothing here makes a sound or asks the real browser: `AudioContext` and
# `Notification` are replaced in the page by fakes that count what they are
# asked for. "Two tabs" are two windows of this one Capybara session, so one
# browser, one person, one cookie -- which is what the tabs' agreement over a
# `BroadcastChannel` is about.
#
# NO WAIT ON TIME. Every tab says when it has made up its mind about a
# delivery (`admin--notes-alert:settled`), so "nothing chimed" is asserted
# after every tab has said so, not after a pause; and a tab that has heard
# another finish never alerts, so nothing can follow.
#
# WHICH TAB IS IN VIEW is said by the test, not left to the browser: the
# headless browser calls the window the test last spoke to visible and the
# other hidden, which would make every two-tab test depend on where the test
# happened to be looking when the signal came. The fakes pin
# `document.hidden` to false; `hide_document` turns it to true. A window the
# browser itself holds to be in the background may have its timers slowed
# (to once a second); every wait here is for a condition and allows for it.
class Admin::NotesAlertSystemTest < ApplicationSystemTestCase
  LIVE = 8

  # A fake AudioContext that counts the tones it is asked for, a fake
  # Notification that records what it is given and can be clicked, and what
  # the tab has settled.
  STUBS = <<~JS.freeze
    window.__hidden = false
    Object.defineProperty(document, "hidden", { get: () => window.__hidden, configurable: true })
    Object.defineProperty(document, "visibilityState", { get: () => (window.__hidden ? "hidden" : "visible"), configurable: true })
    window.__tones = 0
    window.__notified = []
    window.__notifications = []
    window.__settled = []
    document.addEventListener("admin--notes-alert:settled", (event) => window.__settled.push(event.detail))
    const param = () => ({ value: 0, setValueAtTime() {}, exponentialRampToValueAtTime() {} })
    window.AudioContext = class {
      get currentTime() { return 0 }
      get destination() { return {} }
      createGain() { return { gain: param(), connect() {} } }
      createOscillator() { window.__tones += 1; return { frequency: param(), connect() {}, start() {}, stop() {}, addEventListener() {} } }
      resume() { return Promise.resolve() }
      close() { return Promise.resolve() }
    }
    window.Notification = class {
      static permission = "granted"
      static requestPermission() { return Promise.resolve(this.permission) }
      constructor(title, options) { this.handlers = {}; window.__notified.push({ title, body: options.body }); window.__notifications.push(this) }
      addEventListener(name, handler) { this.handlers[name] = handler }
      close() { this.closed = true }
    }
  JS

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    users(:two).update!(name: "Dana")
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @thread = as(users(:two)) { Notes::Start.call(@block, body: "Is this right?") }.record
    sign_in_via_form(users(:one))
  end

  teardown { page.execute_script("try { window.localStorage.removeItem('cs-notes-open') } catch (error) {}") }

  # Dana mentions the signed-in person in a new note on the page; the id of
  # the delivery that tells them.
  def mention_me(body = "Over to you, @[#{users(:one).id}]")
    result = as(users(:two)) { Notes::Start.call(@page, body: body) }
    assert result.ok?, result.errors.inspect
    newest_delivery
  end

  def newest_delivery = Notes::Delivery.where(user: users(:one)).order(:id).last.id

  def stub_alerts = page.execute_script(STUBS)

  # The dashboard with the fakes in place, and a click in the tab: a browser
  # plays no sound before one.
  def stubbed_dashboard(click: true)
    visit "/cs-studio"
    await_notes_live
    stub_alerts
    find("h1").click if click
  end

  # The tab in front of the test has made up its mind about that delivery.
  def await_settled(delivery) = await_js("window.__settled.some((each) => each.id === #{delivery})", wait: LIVE)

  def tones = page.evaluate_script("window.__tones")

  def notified = page.evaluate_script("window.__notified")

  # Another tab is in front of this one, as far as the page can tell.
  def hide_document = page.execute_script("window.__hidden = true; document.dispatchEvent(new Event('visibilitychange'))")

  # --- the chime -------------------------------------------------------------------

  test "a mention chimes once across two tabs, and with a tab in view nothing is put on the desktop" do
    users(:one).update!(notes_desktop: true)
    stubbed_dashboard
    second = open_new_window
    within_window(second) { stubbed_dashboard }

    delivery = mention_me

    await_settled(delivery)
    within_window(second) { await_settled(delivery) }
    # Two tones are one chime: one tab played it, and says so.
    assert_equal 2, tones + within_window(second) { tones }
    chimed = page.evaluate_script("window.__settled.filter((each) => each.chimed).length") + within_window(second) { page.evaluate_script("window.__settled.filter((each) => each.chimed).length") }
    assert_equal 1, chimed
    # Both tabs said it in a toast; the setting is on and the permission
    # given, and still nothing goes to the desktop while a tab is in view.
    assert_selector "#toasts .admin-toast", text: "Dana mentioned you on Pricing"
    within_window(second) { assert_selector "#toasts .admin-toast", text: "Dana mentioned you on Pricing" }
    assert_empty notified + within_window(second) { notified }
  ensure
    second&.close
  end

  test "a tab that is looking at the thread keeps every tab quiet" do
    users(:one).update!(notes_desktop: true)
    visit "/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}"
    await_notes_live
    assert_selector "#notes-drawer [data-notes-view=thread]"
    stub_alerts
    find("#note-thread-#{@thread.id}-reply textarea[name=body]").click
    second = open_new_window
    within_window(second) { stubbed_dashboard }

    result = as(users(:two)) { Notes::Reply.call(@thread, body: "Are you there, @[#{users(:one).id}]?") }
    assert result.ok?, result.errors.inspect
    delivery = newest_delivery

    # The other tab is told, in a toast; the one looking sees it arrive.
    within_window(second) do
      assert_selector "#toasts .admin-toast", text: "Dana mentioned you on Pricing", wait: LIVE
      await_settled(delivery)
    end
    assert_selector "#note-thread-#{@thread.id}-messages [data-note-message]", text: "Are you there", wait: LIVE
    await_settled(delivery)
    assert_no_selector "#toasts .admin-toast"
    assert_equal 0, tones + within_window(second) { tones }
    assert_empty notified + within_window(second) { notified }
  ensure
    second&.close
  end

  # A tab hears the signal in its own time. One whose copy has not come yet
  # is made here by keeping the delivery's announcement from the alert
  # controller altogether: what the tab IS must count on another tab's word.
  def deafen = page.execute_script("document.addEventListener('admin--notes-live:delivery', (event) => event.stopImmediatePropagation(), true)")

  test "a tab in view counts before its own copy of the signal has come: it chimes, and nothing goes to the desktop" do
    users(:one).update!(notes_desktop: true)
    stubbed_dashboard
    deafen
    second = open_new_window
    within_window(second) do
      stubbed_dashboard
      hide_document
    end

    delivery = mention_me

    within_window(second) { await_settled(delivery) }
    await_settled(delivery)
    assert_equal [ 2, 0 ], [ tones, within_window(second) { tones } ]
    assert_empty notified + within_window(second) { notified }
  ensure
    second&.close
  end

  test "a tab looking at the thread says so before its own copy of the signal has come" do
    users(:one).update!(notes_desktop: true)
    visit "/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}"
    await_notes_live
    assert_selector "#notes-drawer [data-notes-view=thread]"
    stub_alerts
    find("#note-thread-#{@thread.id}-reply textarea[name=body]").click
    deafen
    second = open_new_window
    within_window(second) do
      stubbed_dashboard
      hide_document
    end

    result = as(users(:two)) { Notes::Reply.call(@thread, body: "Are you there, @[#{users(:one).id}]?") }
    assert result.ok?, result.errors.inspect
    delivery = newest_delivery

    within_window(second) { await_settled(delivery) }
    await_settled(delivery)
    assert_equal 0, tones + within_window(second) { tones }
    assert_empty notified + within_window(second) { notified }
  ensure
    second&.close
  end

  test "with the sound switched off nothing chimes" do
    users(:one).update!(notes_sound: false)
    stubbed_dashboard

    delivery = mention_me

    assert_selector "#toasts .admin-toast", text: "Dana mentioned you on Pricing", wait: LIVE
    await_settled(delivery)
    assert_equal 0, tones
  end

  test "a reply and a resolve never chime or notify; the mention after them does" do
    users(:one).update!(notes_desktop: true)
    as(users(:one)) { Notes::SetFollowing.call(@thread, following: true) }
    stubbed_dashboard
    hide_document

    as(users(:two)) { Notes::Reply.call(@thread, body: "Just a reply") }
    assert_selector "#toasts .admin-toast", text: "Dana replied", wait: LIVE
    await_settled(newest_delivery)
    as(users(:two)) { Notes::Resolve.call(@thread) }
    assert_selector "#toasts .admin-toast", text: "Dana resolved", wait: LIVE
    await_settled(newest_delivery)
    assert_equal [ 0, [] ], [ tones, notified ]

    # The same tab, the same fakes: they do count.
    await_settled(mention_me)
    assert_equal [ 2, 1 ], [ tones, notified.size ]
  end

  test "a tab that has had no click stays silent, and nothing is kept for later" do
    stubbed_dashboard(click: false)

    await_settled(mention_me)
    assert_equal 0, tones

    find("h1").click
    await_frames
    assert_equal 0, tones
    await_settled(mention_me("And again, @[#{users(:one).id}]"))
    assert_equal 2, tones
  end

  # A browser that cannot make the sound at all: nothing is heard, and the
  # rest goes on -- the notification, the agreement, the tab's own word.
  test "an AudioContext that cannot be made stops neither the notification nor the settling" do
    users(:one).update!(notes_desktop: true)
    stubbed_dashboard
    page.execute_script("window.AudioContext = class { constructor() { throw new Error('no audio device') } }")
    hide_document

    delivery = mention_me

    await_settled(delivery)
    assert_equal [ { "id" => delivery, "chimed" => false, "notified" => true } ], page.evaluate_script("window.__settled")
    assert_equal 1, notified.size
  end

  # --- several notes at once (the handoff's decision 18) ---------------------------

  def named_toasts = all("#toasts .admin-toast[data-note-toast=one]").map(&:text)

  # The window of a burst, for the page in front of the test: both scripts
  # read it from this one value (the alert takes it from the delivery's
  # event), at the moment a delivery is announced.
  def burst_window(milliseconds) = page.execute_script("document.body.setAttribute('data-admin--notes-live-burst-ms-value', '#{milliseconds}')")

  test "two notes at once are two named toasts and one chime; from the third one toast counts them, and the next burst starts over" do
    users(:one).update!(notes_desktop: true)
    stubbed_dashboard
    hide_document

    await_settled(mention_me("First, @[#{users(:one).id}]"))
    await_settled(mention_me("Second, @[#{users(:one).id}]"))

    assert_selector "#toasts .admin-toast[data-note-toast=one]", text: "Dana mentioned you on Pricing", count: 2
    assert_no_selector "#toasts .admin-toast[data-note-toast=many]"
    # One chime and one notification for the burst: the first mention's.
    assert_equal [ 2, 1 ], [ tones, notified.size ]

    await_settled(mention_me("Third, @[#{users(:one).id}]"))

    assert_selector "#toasts .admin-toast[data-note-toast=many]", text: "You have 3 new notes", count: 1
    assert_no_selector "#toasts .admin-toast[data-note-toast=one]"
    assert_selector "#toasts .admin-toast", count: 1
    assert_selector "#toasts .admin-toast[data-note-toast=many] > span[aria-hidden=true][class~='bg-accent']:first-child"
    assert_equal [ 2, 1 ], [ tones, notified.size ]
    page.execute_script("window.__many = document.querySelector('#toasts .admin-toast[data-note-toast=many]')")

    await_settled(mention_me("Fourth, @[#{users(:one).id}]"))

    assert_selector "#toasts .admin-toast[data-note-toast=many]", text: "You have 4 new notes", count: 1
    assert_selector "#toasts .admin-toast", count: 1
    # Put up again, not rewritten: its eight seconds started over.
    assert_equal false, page.evaluate_script("window.__many.isConnected")
    assert_equal [ 2, 1 ], [ tones, notified.size ]

    # The window has passed (here: it is made a millisecond long, and the
    # next delivery comes later than that): a new burst, named and heard.
    burst_window(1)
    await_settled(mention_me("Later, @[#{users(:one).id}]"))

    assert_selector "#toasts .admin-toast[data-note-toast=one]", text: "Dana mentioned you on Pricing", count: 1
    assert_equal [ 4, 2 ], [ tones, notified.size ]

    # "Open" on the one toast for several leads to the inbox.
    within("#toasts .admin-toast[data-note-toast=many]") { press "Open" }
    assert_current_path "/cs-studio/notes"
    assert_selector "h1", text: "Notes for you"
  end

  # A window that is no positive finite number would make a burst that never
  # ends (NaN compares false with everything): the ten seconds stand in.
  test "a burst's window that is not a positive number is ten seconds" do
    stubbed_dashboard
    page.execute_script("window.__windows = []; document.addEventListener('admin--notes-live:delivery', (event) => window.__windows.push(event.detail.burstMs))")

    [ "soon", "0", "-5", "Infinity", "2500" ].each do |value|
      burst_window(value)
      await_settled(mention_me("With #{value}, @[#{users(:one).id}]"))
    end

    assert_equal [ 10_000, 10_000, 10_000, 10_000, 2500 ], page.evaluate_script("window.__windows")
  end

  test "a burst goes on across a Turbo visit: the third note is counted on the next page, without a second chime" do
    stubbed_dashboard
    await_settled(mention_me("First, @[#{users(:one).id}]"))
    await_settled(mention_me("Second, @[#{users(:one).id}]"))
    assert_equal 2, tones

    page.execute_script("window.__visited = false; document.addEventListener('turbo:load', () => { window.__visited = true }, { once: true }); Turbo.visit('/cs-studio/tags')")
    await_js("window.__visited === true", wait: LIVE)
    await_notes_live

    await_settled(mention_me("Third, @[#{users(:one).id}]"))

    assert_selector "#toasts .admin-toast[data-note-toast=many]", text: "You have 3 new notes", count: 1
    assert_no_selector "#toasts .admin-toast[data-note-toast=one]"
    assert_equal 2, tones
  end

  test "a note the person is looking at is not counted among the toasts of a burst" do
    visit "/cs-studio/pages/#{@page.id}?notes=open&thread=#{@thread.id}"
    await_notes_live
    assert_selector "#notes-drawer [data-notes-view=thread]"
    stub_alerts
    find("#note-thread-#{@thread.id}-reply textarea[name=body]").click

    as(users(:two)) { Notes::Reply.call(@thread, body: "Here, @[#{users(:one).id}]") }
    await_settled(newest_delivery)
    assert_no_selector "#toasts .admin-toast"
    await_settled(mention_me("First, @[#{users(:one).id}]"))
    await_settled(mention_me("Second, @[#{users(:one).id}]"))

    # Two were said, so two are named; and the one seen arriving made no
    # sound, so the first that was not seen did.
    assert_selector "#toasts .admin-toast[data-note-toast=one]", count: 2
    assert_no_selector "#toasts .admin-toast[data-note-toast=many]"
    assert_equal 2, tones
  end

  # --- the desktop notification ----------------------------------------------------

  test "with no tab in view one tab of two puts the mention on the desktop, and a click on it opens the thread" do
    users(:one).update!(notes_desktop: true)
    stubbed_dashboard
    hide_document
    second = open_new_window
    within_window(second) do
      stubbed_dashboard
      hide_document
    end

    delivery = mention_me

    await_settled(delivery)
    within_window(second) { await_settled(delivery) }
    raised = notified + within_window(second) { notified }
    # The inbox's sentence, then the record's title and the note's first line.
    assert_equal [ { "title" => "Dana mentioned you", "body" => "Pricing\nOver to you, @one" } ], raised
    assert_equal 2, tones + within_window(second) { tones }

    by = notified.any? ? page.current_window : second
    within_window(by) do
      page.execute_script("window.__notifications[0].handlers.click()")
      assert_selector "#notes-drawer [data-notes-view=thread]", text: "Over to you", wait: LIVE
      assert_current_path(/\/pages\/#{@page.id}\?notes=open&thread=\d+\z/)
      assert page.evaluate_script("window.__notifications[0].closed")
    end
  ensure
    second&.close
  end

  test "the desktop stays quiet with the setting off, and without this browser's permission" do
    stubbed_dashboard
    hide_document

    await_settled(mention_me)
    assert_equal [ 2, [] ], [ tones, notified ]

    users(:one).update!(notes_desktop: true)
    stubbed_dashboard
    hide_document
    page.execute_script("window.Notification.permission = 'default'")

    await_settled(mention_me("Once more, @[#{users(:one).id}]"))
    assert_equal [ 2, [] ], [ tones, notified ]
  end

  # --- the account screen ----------------------------------------------------------

  def permission_row = "[data-controller='admin--notes-permission']"

  # The headless browser has its own answer about notifications; the page is
  # given one, and looks again as it does whenever its window is looked at.
  def browser_says(permission, asked: permission)
    page.execute_script(<<~JS)
      window.__asked = 0
      window.Notification = class {
        static permission = #{permission.to_json}
        static requestPermission() { window.__asked += 1; this.permission = #{asked.to_json}; return Promise.resolve(this.permission) }
      }
      window.dispatchEvent(new Event("focus"))
    JS
  end

  test "the permission line stands only while the desktop switch is on, as it is in the page" do
    visit "/cs-studio/account/password"
    await_admin_controllers
    browser_says("default")
    # Off, as stored: the browser's state is known, and nothing is said.
    assert_selector "#{permission_row}[data-state=default]"
    assert_no_text "This browser has not been allowed"

    find("#notes_desktop").click
    assert_selector "#{permission_row} [data-admin--notes-permission-target=ask][class~='bg-accent-tint']", text: "This browser has not been allowed to show notifications yet."
    assert_selector "#{permission_row} button", text: "Allow in this browser"

    find("#notes_desktop").click
    assert_no_text "This browser has not been allowed"
    assert_no_selector "#{permission_row} button"

    browser_says("denied")
    assert_no_text "Blocked in this browser."
    find("#notes_desktop").click
    # Blocked is the one warn-toned line, and has no button.
    assert_selector "#{permission_row} [data-admin--notes-permission-target=blocked][class~='bg-warn-tint'][class~='border-warn']", text: "Blocked in this browser."
    assert_no_selector "#{permission_row} button"
    assert_equal false, users(:one).reload.notes_desktop
  end

  test "Allow in this browser asks at once, and a browser that refuses says so" do
    visit "/cs-studio/account/password"
    await_admin_controllers
    browser_says("default", asked: "denied")
    find("#notes_desktop").click
    assert_selector "#{permission_row}[data-state=default]", text: "This browser has not been allowed to show notifications yet."

    press "Allow in this browser"

    assert_selector "#{permission_row}[data-state=denied]", text: "Blocked in this browser. Change it in the site settings of your browser."
    assert_no_selector "#{permission_row} button"
    assert_equal 1, page.evaluate_script("window.__asked")
    # Asking the browser saved nothing: the switch is still the one change.
    assert_selector "#profile-form .admin-save-bar", text: "1 unsaved change"
    assert_equal false, users(:one).reload.notes_desktop
  end

  test "a browser that allows it shows no line at all, and one without notifications neither" do
    visit "/cs-studio/account/password"
    await_admin_controllers
    browser_says("default", asked: "granted")
    find("#notes_desktop").click

    press "Allow in this browser"

    assert_selector "#{permission_row}[data-state=granted]"
    assert_no_selector "#{permission_row} button"
    assert_no_text "Blocked in this browser."

    page.execute_script("delete window.Notification; window.dispatchEvent(new Event('focus'))")
    assert_selector "#{permission_row}[data-state=unsupported]"
    assert_no_text "This browser has not been allowed"
  end

  # The handoff's decision 13: the name and the switches are one form.
  test "the name and the two switches are saved by one footer, keep what the password form holds, and reach the next page" do
    visit "/cs-studio/account/password"
    await_admin_controllers
    assert_selector ".admin-save-bar", count: 2
    fill_in "Current password", with: "password"
    fill_in "New password", with: "a-new-long-password"
    fill_in "Confirm new password", with: "a-new-long-password"
    assert_selector "#profile-form button[type=submit][disabled]", text: /\ASave\z/
    assert_selector "#password-form button[type=submit]:not([disabled])", text: "Change password"

    find("#notes_desktop").click
    find("#notes_sound").click
    fill_in "Your name", with: "Olive"

    assert_selector "#profile-form .admin-save-bar", text: "3 unsaved changes"
    # Changing the password would draw the screen again, over the switches.
    assert_selector "#password-form button[type=submit][disabled]", text: "Change password"
    assert_selector "#password-form .admin-save-bar [role=status]", text: "Save or cancel your changes first."
    assert_equal [ nil, true, false ], users(:one).reload.then { |user| [ user.name, user.notes_sound, user.notes_desktop ] }

    within("#profile-form") { press "Save" }

    assert_selector "#profile-form .admin-save-bar", text: "No unsaved changes", wait: LIVE
    assert_no_selector "dialog#leave-dialog[open]"
    assert_equal [ "Olive", false, true ], users(:one).reload.then { |user| [ user.name, user.notes_sound, user.notes_desktop ] }
    assert_equal 1, Audit::Event.where(action: "user.updated", subject: users(:one)).count
    assert_selector "#password-form button[type=submit]:not([disabled])", text: "Change password"
    assert_equal "a-new-long-password", find_field("New password").value
    assert_equal [ true, false ], [ find("#notes_desktop").checked?, find("#notes_sound").checked? ]

    # The settings a tab acts on are those of the page it drew: the next one.
    # (The typed password is given up first, or leaving would ask about it.)
    fill_in "New password", with: ""
    fill_in "Confirm new password", with: ""
    assert_selector "#password-form .admin-save-bar", text: "No unsaved changes"
    assert_selector "body[data-admin--notes-alert-sound-value=true][data-admin--notes-alert-desktop-value=false]"
    visit "/cs-studio"
    assert_selector "body[data-admin--notes-alert-sound-value=false][data-admin--notes-alert-desktop-value=true]"
  end
end
