require "application_system_test_case"

# "Sign in with a passkey" as a person meets it, with Chrome's virtual
# authenticator in place of a device (`PasskeyHelper#with_virtual_authenticator`):
# the page's own `navigator.credentials.get` signs the server's challenge
# with a credential the test handed the authenticator, and the server checks
# it as it checks a real one.
#
# The sign-in page loads the `application` entry point only, so a test
# waits for what the page shows: the button, enabled once its options have
# arrived (`passkey-sign-in`).
class Admin::PasskeySignInSystemTest < ApplicationSystemTestCase
  BUTTON = "button[data-passkey-sign-in-target=button]".freeze
  READY = "#{BUTTON}:not([hidden]):not([disabled])".freeze
  DIVIDER = "[data-passkey-sign-in-target=divider]".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @user = users(:one)
  end

  test "Sign in with a passkey signs in and lands on the dashboard" do
    with_virtual_authenticator do |authenticator|
      passkey = add_virtual_passkey(@user, authenticator)
      visit admin_sign_in_path
      assert_selector DIVIDER, text: "or"
      assert_selector READY, text: "Sign in with a passkey"

      press "Sign in with a passkey"

      assert_selector "nav[aria-label='Modules']", wait: 15
      assert_equal "passkey", Session.sole.authenticated_with
      assert_not_nil passkey.reload.last_used_at
    end
  end

  # The options' answers the page has had, finished (the page's own record
  # of them, which a fetch joins once its answer is in).
  OPTIONS_FETCHED = "performance.getEntriesByType('resource').filter((entry) => entry.name.endsWith('/sign-in/passkey/options')).length".freeze

  def options_fetched = page.evaluate_script(OPTIONS_FETCHED)

  # The server's clock is moved past the challenge's lifetime, which the page's
  # clock does not follow: the options the page held at load would be refused,
  # so only a fresh set signs in.
  test "a tab shown again fetches fresh options, so a page left open past five minutes still signs in" do
    with_virtual_authenticator do |authenticator|
      add_virtual_passkey(@user, authenticator)
      visit admin_sign_in_path
      assert_selector READY
      fetched = options_fetched
      travel PasskeyChallenges::LIFETIME + 1.minute

      page.execute_script("document.dispatchEvent(new Event('visibilitychange'))")
      await_js("#{OPTIONS_FETCHED} > #{fetched}")
      await_frames
      press "Sign in with a passkey"

      assert_selector "nav[aria-label='Modules']", wait: 15
      assert_equal 1, Session.count
    end
  end

  # The page's clock (`performance.now`, which `passkeys/held_options` reads)
  # is moved five minutes on, as a computer that slept with the page open
  # finds it, and the server's with it: only the fresh set fetched in the
  # press signs in.
  test "a press on options too old to use fetches fresh ones first and signs in" do
    with_virtual_authenticator do |authenticator|
      add_virtual_passkey(@user, authenticator)
      visit admin_sign_in_path
      assert_selector READY
      travel PasskeyChallenges::LIFETIME
      page.execute_script(<<~JS)
        const real = performance.now.bind(performance)
        performance.now = () => real() + 5 * 60 * 1000
      JS

      press "Sign in with a passkey"

      assert_selector "nav[aria-label='Modules']", wait: 15
      assert_equal 1, Session.count
    end
  end

  # The stub refuses the first call as a closed prompt does and hands every
  # later one to the browser's own `get`, which it kept.
  test "a cancelled prompt says nothing and the button works again" do
    with_virtual_authenticator do |authenticator|
      add_virtual_passkey(@user, authenticator)
      visit admin_sign_in_path
      assert_selector READY
      page.execute_script(<<~JS)
        const real = navigator.credentials.get.bind(navigator.credentials)
        window.passkeyCalls = 0
        navigator.credentials.get = (options) => {
          window.passkeyCalls += 1
          if (window.passkeyCalls === 1) return Promise.reject(new DOMException("The prompt was closed.", "NotAllowedError"))
          return real(options)
        }
      JS

      press "Sign in with a passkey"

      await_js("window.passkeyCalls === 1")
      assert_selector READY
      assert_no_text I18n.t("admin.sessions.passkey_failed")
      assert_current_path admin_sign_in_path
      assert_equal 0, Session.count

      press "Sign in with a passkey"

      assert_selector "nav[aria-label='Modules']", wait: 15
    end
  end

  test "without WebAuthn the divider and the button stay hidden" do
    script = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: "delete window.PublicKeyCredential")
    on_localhost do
      visit admin_sign_in_path
      assert_selector "input[name=email_address]"
      await_js("window.Stimulus && window.Stimulus.controllers.some((controller) => controller.identifier === 'passkey-sign-in')")
      await_frames

      assert_selector BUTTON, visible: :hidden
      assert_selector DIVIDER, visible: :hidden
      assert_no_button "Sign in with a passkey"
      assert_empty page.driver.browser.network.traffic.map { |exchange| exchange.request.url }.grep(%r{/sign-in/passkey}),
        "no options are asked for where no passkey can be used"
    end
  ensure
    page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: script["identifier"]) if script
  end
end
