require "application_system_test_case"

# Final fix wave (D): the sign-in page imports the `application` entry
# point, CS Studio imports `admin`. Signing in is a Turbo form submission,
# not a full page load, so this proves the `admin` entry point still runs
# on that path (Turbo appends and runs a `<head>` script the new page has
# and the old one didn't) -- CS Studio must never render after sign-in with
# its own controllers unregistered.
class Admin::EntryPointTest < ApplicationSystemTestCase
  test "signing in lands on a CS Studio whose admin controllers are running" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))

    registered = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      const deadline = Date.now() + 5000
      const poll = () => {
        const ids = window.Stimulus ? Array.from(window.Stimulus.router.modulesByIdentifier.keys()) : []
        if (ids.includes("admin--pages--tree") || Date.now() > deadline) return done(ids)
        setTimeout(poll, 20)
      }
      poll()
    JS
    assert_includes registered, "admin--pages--tree"
  end
end
