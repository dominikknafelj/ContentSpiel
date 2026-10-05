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

  # Stimulus catches what an action throws and writes it with `console.error`
  # (no CDP exception), so these are the cases the collector's console half is
  # for.
  def register_stimulus_probe(body)
    page.execute_script(<<~JS, body)
      import("@hotwired/stimulus").then(async ({ Controller }) => {
        const { messages } = await import("i18n/messages")
        const run = Function("messages", "element", arguments[0])
        Stimulus.register("probe", class extends Controller { go() { run(messages, this.element) } })
        document.body.insertAdjacentHTML("beforeend", '<button id="probe" data-controller="probe" data-action="click->probe#go">x</button>')
      })
    JS
    assert_selector "#probe"
  end

  test "an error thrown inside a Stimulus action is collected" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    await_admin_controllers
    register_stimulus_probe("throw new Error('thrown in an action')")
    find("#probe").click
    expect_js_error(/thrown in an action/)
  end

  test "a missing message key inside a Stimulus action is collected" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    await_admin_controllers
    register_stimulus_probe(%(messages(element).t("no.such.key")))
    find("#probe").click
    expect_js_error(/no message "no.such.key"/)
  end

  test "a console.error of an Error carries the first line of its stack" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    page.execute_script("console.error(new TypeError('with a stack'))")
    expect_js_error(/TypeError: with a stack \(at /)
  end

  test "a plain console.error is collected and console.warn is not" do
    sign_in_via_form(users(:one))
    visit admin_root_path
    page.execute_script("console.warn('only a warning'); console.error('an error', 3)")
    expect_js_error(/an error 3/)
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
