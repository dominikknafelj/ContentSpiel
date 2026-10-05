require "application_system_test_case"

class JsErrorsTest < ApplicationSystemTestCase
  test "an uncaught error on the page is collected" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    page.execute_script("setTimeout(() => { throw new Error('boom from the page') }, 0)")
    assert_eventually(message: "the error was never collected") { JsErrorCollector.errors.any? }
    assert_match "boom from the page", JsErrorCollector.errors.first[:message]
  ensure
    JsErrorCollector.reset! # this test's error is the subject, not a failure
  end

  test "an unhandled rejection is collected" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    page.execute_script("Promise.reject(new Error('rejected on the page'))")
    assert_eventually(message: "the rejection was never collected") { JsErrorCollector.errors.any? }
    assert_match "rejected on the page", JsErrorCollector.errors.first[:message]
  ensure
    JsErrorCollector.reset!
  end

  test "Turbo's aborted frame fetch is ignored, with its reason on record" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    page.execute_script(<<~JS)
      const error = new DOMException("The user aborted a request.", "AbortError")
      Promise.reject(error)
    JS
    sleep 0.3 # sleep: proves an absence; no event marks an error that was dropped
    assert_empty JsErrorCollector.errors
    assert JsErrorCollector::IGNORED.all? { |_matcher, reason| reason.present? }
  end

  test "an expected error is taken out of the collector and does not fail the test" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    page.execute_script("setTimeout(() => { throw new Error('provoked on purpose') }, 0)")
    expect_js_error(/provoked on purpose/)
    assert_empty JsErrorCollector.errors
  end
end
