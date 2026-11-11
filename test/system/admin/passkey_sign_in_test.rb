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
