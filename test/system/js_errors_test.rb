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

  test "an AbortError from our own code is collected, not ignored" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    page.execute_script(<<~JS)
      Promise.reject(new DOMException("The user aborted a request.", "AbortError"))
    JS
    expect_js_error(/AbortError/)
  end

  test "Turbo's aborted frame fetch is ignored, and the collector is still alive after it" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    # No Turbo-shaped error can be made from the page, so the ignored one is
    # recorded directly; the sentinel then proves the collector is alive (events
    # arrive in order, so everything before it has been judged).
    JsErrorCollector.record(turbo_abort_details)
    page.execute_script("setTimeout(() => { throw new Error('sentinel after the abort') }, 0)")
    assert_eventually(message: "the sentinel never arrived") { JsErrorCollector.consume(/sentinel after the abort/) }
    assert_empty JsErrorCollector.errors
    assert JsErrorCollector::IGNORED.all? { |_matcher, reason| reason.present? }
  end

  test "an AbortError is ignored only with the Turbo bundle in its url or stack" do
    JsErrorCollector.reset!
    JsErrorCollector.record(turbo_abort_details)
    JsErrorCollector.record(turbo_abort_details(url: "http://127.0.0.1:1/assets/application-0123abcd.js"))
    JsErrorCollector.record(turbo_abort_details(url: "", frame_url: "http://127.0.0.1:1/assets/turbo.min-9fd88cd5.js").merge("url" => ""))
    errors = JsErrorCollector.errors
    assert_equal 1, errors.size
    assert_match "AbortError", errors.first[:message]
    assert_match "application-0123abcd", errors.first[:url]
  ensure
    JsErrorCollector.reset!
  end

  test "an expected error is taken out of the collector and does not fail the test" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    page.execute_script("setTimeout(() => { throw new Error('provoked on purpose') }, 0)")
    expect_js_error(/provoked on purpose/)
    assert_empty JsErrorCollector.errors
  end

  private

  # A Turbo-shaped `exceptionDetails`: the bare text, the message in the
  # exception's description, and Turbo's bundle as url and frame.
  def turbo_abort_details(url: "http://127.0.0.1:1/assets/turbo.min-9fd88cd5.js", frame_url: url)
    {
      "text" => "Uncaught (in promise)", "url" => url,
      "stackTrace" => { "callFrames" => [ { "functionName" => "loadResponse", "url" => frame_url, "lineNumber" => 1 } ] },
      "exception" => { "className" => "AbortError", "description" => "AbortError: signal is aborted without reason\n    at x" }
    }
  end
end
