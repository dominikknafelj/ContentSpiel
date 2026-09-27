require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  # Signs in through the real sign-in form (cs-studio spec §3/§9). `Session
  # TestHelper#sign_in_as` -- what every integration test uses -- only ever
  # sets cookies on the test process's own internal Rack::Test session; a
  # system test's browser is a *separate* HTTP client Selenium drives, so
  # cookies set that way never reach it. Signing in has to happen the way a
  # real editor would: an actual POST the browser itself sends.
  def sign_in_via_form(user, password: "password")
    visit admin_sign_in_path
    fill_in "Enter your email address", with: user.email_address
    fill_in "Enter your password", with: password
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

  # Clicks through JavaScript (`element.click()`) instead of a native
  # WebDriver click -- see `test/system/setup_wizard_test.rb`'s own comment
  # for why: on a loaded machine headless Chrome intermittently drops native
  # clicks made right after a page load. Shared here (carried out of that
  # test, cs-studio Task 9) since every CS Studio system test needs the same
  # workaround for its own sign-in and navigation clicks.
  def press(label)
    find(:link_or_button, label).execute_script("this.click()")
  end
end
