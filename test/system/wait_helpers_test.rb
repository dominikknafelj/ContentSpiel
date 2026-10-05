require "application_system_test_case"

# `await_js` and `assert_writes_settled` take their own `wait:`: Cuprite
# would otherwise reject the async script after `Capybara.default_max_wait_time`
# (2 s) with a driver error, and the helpers' own messages would never show.
class WaitHelpersSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_via_form(users(:one))
  end

  test "await_js waits past the driver's own default for a condition that becomes true later" do
    page.execute_script("window.__ready = false; setTimeout(() => { window.__ready = true }, 3000)")
    await_js "window.__ready === true", wait: 4
  end

  test "await_js fails with its own message when the condition never holds" do
    failure = assert_raises(Minitest::Assertion) { await_js "window.__never === true", wait: 3 }
    assert_match(/timed out waiting for: window.__never === true/, failure.message)
  end
end
