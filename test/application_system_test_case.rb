require "test_helper"
require "capybara/cuprite"
require_relative "support/js_error_collector"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Cuprite drives headless Chrome over the DevTools protocol (via Ferrum),
  # dispatching clicks and key events straight to the page with
  # `Input.dispatch*Event`. It replaced Selenium (PR #30): WebDriver's
  # keyboard actions intermittently never reached a fully rendered, focused
  # page on CI -- one unrelated system test per run, never locally -- and a
  # handshake that waited for native input couldn't make them arrive.
  #
  # `js_errors: false`: with `true`, Ferrum raises the page's uncaught
  # exceptions into the test thread with `Thread.main.raise`, at whatever line
  # it happens to be on, with no way to exempt one. `JsErrorCollector`
  # (prepended onto `Ferrum::Page` below) listens for the same CDP event
  # instead and records the errors; `teardown` fails the test that caused
  # them, naming each. The one error the application can't prevent -- Turbo's
  # `AbortError` from a `<turbo-frame>` disconnected mid-load, which flaked the
  # API-token test's `go_back` -- is listed with its reason in
  # `JsErrorCollector::IGNORED`.
  # `no-sandbox` because GitHub's runners (and most containers) can't give
  # Chrome its user-namespace sandbox.
  driven_by :cuprite, screen_size: [ 1400, 1400 ], options: {
    headless: true,
    js_errors: false,
    process_timeout: 30,
    timeout: 15,
    browser_options: { "no-sandbox" => nil }
  }

  # A node whose page has been replaced is stale AT ONCE.
  #
  # Before every command on a node, Cuprite asks `this.isConnected` through
  # Ferrum's `evaluate`, which first resolves the node's CDP id
  # (`DOM.resolveNode`) and -- when Chrome answers "No node with given id
  # found" -- retries that six times, 0.1 s apart, before giving up
  # (`Ferrum::Frame::Runtime#call`, `INTERMITTENT_ATTEMPTS`/`_SLEEP`). Only
  # then does Cuprite raise `ObsoleteNode`, which is what Capybara is waiting
  # for to run its query again. A dead id never comes back, so that is half a
  # second of nothing, PER NODE.
  #
  # A Turbo visit kills every id a poll is holding: it pushes a history entry
  # (`Page.navigatedWithinDocument`, on which Ferrum re-reads the document
  # with `DOM.getDocument`, resetting Chrome's node ids) and swaps the
  # `<body>`. So an `assert_selector "[role=status]", text: ...` whose poll
  # was in the middle of reading the old page when the redirect rendered went
  # through each element it had found -- to filter it, then again to print
  # "Also found ..." -- at 0.5 s apiece: with an editor's seven
  # `[role=status]` elements, 4.4 s without looking at the page once. A
  # success toast stays 4 s (`Admin::ToastComponent::TIMEOUTS`): it was
  # rendered, shown and dismissed on time while the driver was blind, and the
  # assertion then failed on a page that no longer had it. That was the
  # "Undo from the flash" failure of about one run in ten (and "Emptied the
  # trash", "Restored ..." under load) -- found in the CDP log of a failing
  # run, where the app had made one request and drawn the toast.
  #
  # So the question "is this id still alive?" is asked once, without retries
  # (`Ferrum::Node#exists?`: a single `DOM.resolveNode`), and a dead node is
  # reported straight away. Capybara's own polling loop is the retry. A node
  # that dies between this check and the command still costs its half second
  # -- once per poll, not once per element. `test/system/stale_node_test.rb`
  # pins it.
  module StaleNodeAtOnce
    def command(name, *args)
      raise Capybara::Cuprite::ObsoleteNode.new(self, nil) unless node.exists?

      super
    end
  end
  Capybara::Cuprite::Node.prepend(StaleNodeAtOnce)
  Ferrum::Page.prepend(JsErrorCollector)

  # The collector is process-wide (a test process runs one browser at a time),
  # so it is emptied before each test; the page is a fresh one per test, so a
  # late event from the previous test's page is a stale one at worst.
  setup { JsErrorCollector.reset! }

  # For a test that provokes a JavaScript error on purpose (a request made to
  # fail, a response Turbo refuses): waits for an error whose message matches
  # and takes it out of the collector, so `teardown` doesn't fail the test for
  # it. The test fails if the error never comes.
  def expect_js_error(pattern)
    assert_eventually(message: "no JavaScript error matching #{pattern.inspect} reached the page") { JsErrorCollector.consume(pattern) }
  end

  # Fails a test that otherwise passed because its page raised an error. A test
  # that failed on its own keeps its own failure (`passed?`), which is the one
  # worth reading.
  teardown do
    errors = JsErrorCollector.errors
    JsErrorCollector.reset!
    if errors.any? && passed?
      flunk "JavaScript errors on the page:\n" + errors.map { |e|
        "  #{e[:message]} (#{e[:url]})#{" at #{e[:frame]}" if e[:frame]}"
      }.join("\n")
    end
  end

  # Signs in through the real sign-in form (cs-studio spec §3/§9). `Session
  # TestHelper#sign_in_as` -- what every integration test uses -- only ever
  # sets cookies on the test process's own internal Rack::Test session; a
  # system test's browser is a *separate* HTTP client Cuprite drives, so
  # cookies set that way never reach it. Signing in has to happen the way a
  # real editor would: an actual POST the browser itself sends.
  def sign_in_via_form(user, password: "password")
    visit admin_sign_in_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: password
    press "Sign in"

    # `press`'s own click fires a real (async) browser form submission --
    # sign-in redirects to CS Studio's own shell, so waiting for its
    # "Modules" nav (rather than just returning immediately) is what makes
    # sure the session cookie the redirect sets has actually landed before
    # a caller's next `visit` fires. Without this, a caller moving straight
    # on to its own `visit` could race the still-in-flight sign-in POST,
    # navigate away before its `Set-Cookie` response ever arrives, and land
    # right back on the sign-in page, unauthenticated.
    assert_selector "nav[aria-label='Modules']"
  end

  # Opens the editor header's ⋯ menu (Activity, Schedule…, Unpublish, Move to
  # trash live in it), waiting until its panel is shown.
  def open_editor_menu
    find("header.admin-editor-header button[aria-label='More actions']").click
    assert_selector "header.admin-editor-header [role=menu]"
  end

  # Clicks the way a person does: a native pointer click at the element's
  # centre (Cuprite scrolls it into view first). A button another element
  # covers -- a sticky footer, a dialog's backdrop, an overlapping panel --
  # raises `Capybara::Cuprite::MouseEventFailed` and one inside a closed menu
  # is not found, which is the point: a control a person can't press is a
  # defect of the layout or of the test, and a scripted click hides both. The
  # related-posts picker is a case in point: a native click there once lost
  # the pick, because the autosave its mousedown started grew the empty
  # save-status line and moved the button out from under the mouseup
  # (`Admin::SaveStatusComponent` now reserves that line).
  def press(label)
    find(:link_or_button, label).click
  end

  # The scripted click (`element.click()`), for the cases a native click
  # changes what the test exercises. Every call carries a one-line comment
  # naming which:
  #   - the element is inside a closed menu the test reaches by other means;
  #   - the control is shown only by a `hover:` style, which CI's headless
  #     Chrome (no hover device) never applies;
  #   - a native click would change the thing under test (a `mousedown` that
  #     starts an autosave and moves the target; ProseMirror's node
  #     selection), or the test builds a same-tick race on purpose.
  def press_by_script(label)
    find(:link_or_button, label).execute_script("this.click()")
  end

  # Follows a link into the `#content` frame and waits until Turbo has finished
  # with it. Such a link (a media tile, a trash tab, a list row, the users
  # list's "New user") renders the frame and is then promoted to a page visit
  # (`data-turbo-action="advance"`): `turbo:load` fires a few dozen ms AFTER the
  # new content is on the page, and until then the page is still arriving -- a
  # field typed into can be re-rendered, a Back pressed can be cancelled by the
  # late visit, a link clicked can lose to it. No person is that fast; a
  # scripted browser is. So a test that goes on to READ or use the new screen
  # clicks through here, and no test keeps its own copy of this wait.
  #
  #   click_frame_link "New user"                              # a link, by text
  #   click_frame_link { find("#media-asset-7 a").click }      # anything else
  #
  # The block form also serves a form whose answer redirects inside the frame
  # (Create user): that render is promoted the same way.
  #
  # The write queue itself holds a non-GET form pressed in that window (the
  # "promotion hold", `autosave/queue.js`), so a write is no longer lost
  # there; `test/system/admin/promotion_hold_test.rb` presses without this
  # wait on purpose, and must keep doing so.
  def click_frame_link(locator = nil, **options)
    page.execute_script("window.__frameLinkLoaded = false; document.addEventListener('turbo:load', () => { window.__frameLinkLoaded = true }, { once: true })")
    block_given? ? yield : click_link(locator, **options)
    assert_eventually(message: "the visit the frame navigation is promoted to never finished (no turbo:load)") { page.evaluate_script("window.__frameLinkLoaded === true") }
  end

  # A rich-text editor's Insert menu item (Page link, Image, YouTube,
  # Divider): opens the menu, then presses the item -- which is only
  # *visible* (so findable) while the menu is open, which is part of what
  # this checks. `within:` scopes to one editor's toolbar when a page has
  # several.
  def press_insert(label, within: "[role=toolbar]")
    find("#{within} button[aria-haspopup=menu]", match: :first).click
    find("#{within} [role=menu] button", text: label, match: :first).click
  end

  # CS Studio's Stimulus controllers (`controllers/admin/*`) are registered
  # by the `admin` entry point (app/javascript/admin.js) through one dynamic
  # `import()` each, so they connect a moment *after* the page has loaded,
  # even though they're modulepreloaded. A test that types right after
  # `visit` can race them -- before `admin--autosave` is connected its
  # `input` events go nowhere. So this waits until every `admin--*`
  # controller named on the page is connected.
  #
  # Cuprite needs no further wait before typing: its key events go to the
  # page through CDP rather than through a WebDriver input queue, so there
  # is no separate "accepting native input" state to wait for (Selenium
  # needed an `await_native_input` handshake here, which is what flaked).
  # Polls a condition on the database (a save the browser sends on its own
  # timer) until it holds, `wait` seconds at most.
  def assert_eventually(wait: 8, message: "condition never became true")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + wait
    until yield
      flunk message if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.1
    end
    assert true
  end

  def await_admin_controllers
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      const ready = () => {
        const app = window.Stimulus
        if (!app) return false
        return Array.from(document.querySelectorAll("[data-controller*='admin--']")).every((element) =>
          element.getAttribute("data-controller").split(" ").filter((name) => name.startsWith("admin--"))
            .every((name) => app.getControllerForElementAndIdentifier(element, name)))
      }
      const poll = () => (ready() ? done(true) : setTimeout(poll, 20))
      poll()
    JS
  end
end
