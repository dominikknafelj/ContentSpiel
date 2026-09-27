require "application_system_test_case"

# The page settings form's own autosave (cs-studio spec §6.1/§9): a debounced
# PATCH, the status line's exact wording (global constraints), and the
# "one in-flight save, at most one queued" concurrency rule
# `admin--autosave` itself is built around (see that controller's own class
# comment). System-level, not integration-level, because both of these need
# a real browser's own timers/`fetch` -- neither is observable through a
# plain Rack request.
class Admin::AutosaveSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
    @page = create_page(title: "About")
  end

  test "typing in the page title autosaves and persists" do
    visit "/cs-studio/pages/#{@page.id}"

    fill_in "Title", with: "About the Studio"

    # Capybara's `assert_selector` polls until this appears (or times out),
    # so this alone is what actually waits out the 1000ms debounce -- no
    # `sleep` needed. Asserting the eventual "Saved HH:MM" rather than the
    # transient "Saving…" (the brief's own either/or) sidesteps a real race:
    # a fast local save can move through "Saving…" and back out again
    # between two of Capybara's polls, which would make asserting that
    # specific interim state itself flaky. `assert_selector(id, text:,
    # wait:)` in one call, not `within(id) { assert_text(..., wait:) }` --
    # `within` locates its scoping element with Capybara's *default* wait
    # (2s) before the block (and its own explicit `wait:`) ever runs, so a
    # `within` whose target hasn't rendered yet (or was just replaced by an
    # earlier Turbo Stream) can raise `ElementNotFound` well before the
    # longer wait this assertion actually needs gets any say. Scoped to the
    # status line itself (`page-save-status`, in the record header -- see
    # `admin--autosave`'s own comment for why it lives outside this form's
    # DOM subtree) rather than the whole page, since the exact wording
    # (global constraints) is this element's *entire* text content, not
    # just some text on the page.
    assert_selector "#page-save-status", text: /\ASaved \d{2}:\d{2}\z/, wait: 5

    assert_equal "About the Studio", @page.reload.title(locale: :en)
  end

  # Review focus #1 (this task's own brief): a second edit made while the
  # first save is still in flight must be the one that wins -- never the
  # first attempt's stale value landing *after* the second request, and
  # never both firing at once and racing each other. `admin--autosave`'s own
  # `busy`/`pending` flags (see that controller's class comment) are what
  # this proves: exactly one request in flight, the newest edit always the
  # next (and last) one sent.
  test "a second quick edit wins over the first save even while it's still in flight" do
    visit "/cs-studio/pages/#{@page.id}"

    # Slows every `fetch` call by half a second before it's even issued --
    # a JS-side stub (the brief's own suggested approach) rather than a
    # server-side hook, so no production code has to grow a test-only delay
    # switch. Long enough that the two edits below reliably land while the
    # first attempt's request is still outstanding, short enough this test
    # doesn't drag.
    page.execute_script(<<~JS)
      const originalFetch = window.fetch
      window.fetch = (...args) => new Promise((resolve) => {
        window.setTimeout(() => resolve(originalFetch(...args)), 500)
      })
    JS

    # `Tab` blurs the field with a native key event on an element that's
    # already focused, rather than a fresh click on some other element --
    # sidesteps the native-click-drop risk `press`'s own comment describes
    # entirely, since there's no click here at all. `focusout` ->
    # `admin--autosave#saveNow` fires the save immediately, with no
    # debounce wait.
    title_field = find_field("Title")
    title_field.set("First edit")
    title_field.send_keys(:tab)

    # Confirms the first attempt is actually under way (and thus `busy`)
    # before the second edit below has any chance of racing ahead of it.
    assert_selector "#page-save-status", text: "Saving…"

    title_field = find_field("Title")
    title_field.set("Second edit wins")
    title_field.send_keys(:tab)

    # The first attempt's delayed fetch resolves, `admin--autosave` notices
    # `pending` and immediately fires the second attempt (itself delayed by
    # the same stub) with whatever the form holds *now*.
    #
    # Polling the database directly, rather than asserting the status
    # line's own final text, sidesteps a *second*, unrelated race this test
    # exposed while being written: `Turbo.renderStreamMessage` applies a
    # `<turbo-stream>` response on the browser's next animation frame, not
    # synchronously -- so the *first* attempt's own deferred "Saved"
    # replace can still land (and visually flash) *after* the second
    # attempt has already moved the status back to "Saving…", which is
    # enough to fool `assert_text` into matching a stale "Saved" from the
    # first save rather than waiting for the second one to actually finish.
    # The database write is the one thing that can't lie about which save
    # actually landed last.
    assert_page_title_eventually("Second edit wins")
  end

  # Fix (final-fixes round, finding 4): a session that expired between this
  # page loading and the very next autosave firing used to leave the status
  # line stuck on "Saving…" forever -- `fetch`'s own default `redirect:
  # "follow"` quietly turns the server's 302-to-sign-in into a *followed*,
  # final 200 response for the sign-in page itself, which the original code
  # then handed straight to `Turbo.renderStreamMessage` as if it were a real
  # answer. Destroying the signed-in user's own session row server-side
  # (rather than clearing the browser's cookie, which `resume_session`'s own
  # `cookies.signed[:session_id]` lookup would just as happily accept a
  # fresh one for) is what reproduces "signed in a moment ago, expired
  # since" without touching anything this test doesn't own.
  test "an autosave whose session expired meanwhile shows Signed out, not stuck on Saving forever" do
    visit "/cs-studio/pages/#{@page.id}"
    users(:one).sessions.destroy_all

    title_field = find_field("Title")
    title_field.set("Nobody is signed in anymore")
    title_field.send_keys(:tab)

    assert_selector "#page-save-status", text: "Signed out — sign in again to keep saving", wait: 5
  end

  # Fix (final-fixes round, finding 4): a response that arrives but isn't
  # this endpoint's own Turbo Stream answer (a 500, here) used to be handed
  # to `Turbo.renderStreamMessage` exactly like a real success -- no
  # `<turbo-stream>` tags in it for Turbo to act on, so nothing visibly
  # happened, but the status line never moved off "Saving…" either. `fetch`
  # is stubbed here (the same technique the "second edit wins" test above
  # already uses) rather than the server actually 500ing, since nothing in
  # this app can be made to fail on demand; `window.setTimeout` is stubbed
  # alongside it purely to collapse this controller's own 1s/3s/9s retry
  # backoff so the test doesn't have to sit through 13 real seconds of it.
  test "a response that isn't a real answer (a 500, not a turbo-stream) retries, then shows check your connection" do
    visit "/cs-studio/pages/#{@page.id}"

    page.execute_script(<<~JS)
      const originalSetTimeout = window.setTimeout
      window.setTimeout = (fn, _delay) => originalSetTimeout(fn, 0)
      window.fetch = () => Promise.resolve(new Response("Internal Server Error", { status: 500, headers: { "Content-Type": "text/plain" } }))
    JS

    title_field = find_field("Title")
    title_field.set("This will never actually save")
    title_field.send_keys(:tab)

    assert_selector "#page-save-status", text: "Not saved — check your connection", wait: 5
  end

  private

  # See this test's own comment for why the status line's text alone isn't
  # a trustworthy signal that the *second* save (specifically) has landed.
  def assert_page_title_eventually(title)
    deadline = Time.current + 5.seconds

    loop do
      current = @page.reload.title(locale: :en)
      break if current == title
      raise Minitest::Assertion, "expected the page title to become #{title.inspect}, got #{current.inspect}" if Time.current > deadline

      sleep 0.1
    end
  end
end
