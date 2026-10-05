# Collects every uncaught exception and unhandled promise rejection a system
# test's page raises, so `ApplicationSystemTestCase` can fail the test that
# caused it. Chrome reports both kinds as one CDP event,
# `Runtime.exceptionThrown`; `details` below is that event's
# `exceptionDetails`: `"text"`, `"url"`, `"stackTrace"` and, sometimes,
# `"exception"` (`"className"`, `"description"`: the error's `name: message`
# and stack as text). Which of them carries the message depends on where the
# error came from, so `message` joins them:
#
#   an error thrown or rejected from script run by the test:
#     text "Uncaught (in promise) Error: boom", no "exception"
#   an error thrown inside the application's own bundles (Turbo):
#     text "Uncaught (in promise)", exception.description "TypeError: Failed to fetch\n at ..."
#
# Errors written with `console.error` are not exceptions and are not collected.
#
# This is prepended onto `Ferrum::Page` rather than using the driver's own
# `js_errors: true`: that option does `Thread.main.raise` from the CDP thread,
# landing at an arbitrary line of the test (inside a Capybara wait, a DB poll,
# a `sleep`), can't be filtered, and its exception can be swallowed by the very
# code it interrupts. Collecting and failing in `teardown` blames the right
# test at a fixed place.
module JsErrorCollector
  # Errors the application cannot prevent, each with the reason it can't. A
  # matcher gets the CDP `exceptionDetails` hash and must be as narrow as the
  # one error it names: widening one to silence a new failure hides defects.
  #
  # Turbo's bundle is served as `/assets/turbo.min-<digest>.js` (the importmap
  # pin `turbo.min.js`).
  TURBO_BUNDLE = %r{/assets/turbo\.min[-.]}

  IGNORED = [
    [
      ->(details) {
        urls = [ details["url"], *details.dig("stackTrace", "callFrames")&.map { |frame| frame["url"] } ]
        JsErrorCollector.message_of(details).match?(/\AUncaught \(in promise\) AbortError\b/) &&
          urls.any? { |url| url.to_s.match?(TURBO_BUNDLE) }
      },
      "Turbo: a <turbo-frame> disconnected mid-load aborts its fetch and the AbortError escapes unhandled " \
      "(an unawaited read on the aborted response, with the Turbo bundle in its stack). Only an AbortError " \
      "that comes from the Turbo bundle is ignored; one from our own code is a defect. The real error's " \
      "shape was never reproduced (the matcher is built from the Turbo-shaped errors that were seen: bare " \
      "text \"Uncaught (in promise)\", exception.description \"AbortError: ...\", Turbo's url): if the " \
      "flake surfaces with another shape, adjust this matcher from the failure's message and frame."
    ]
  ].freeze

  @errors = []
  @lock = Mutex.new

  class << self
    def errors = @lock.synchronize { @errors.dup }

    def reset! = @lock.synchronize { @errors.clear }

    # What the error says, first line only: "Uncaught (in promise) <name:
    # message>", the text and the exception's description when both exist.
    def message_of(details)
      text = details["text"].to_s
      description = details.dig("exception", "description").to_s.lines.first.to_s.strip
      [ text, description ].reject(&:empty?).join(" ")
    end

    # A test that provokes an error on purpose (a request made to fail, a
    # response Turbo refuses) says so with `expect_js_error`; this removes the
    # first collected error whose message matches and answers whether there
    # was one.
    def consume(pattern)
      @lock.synchronize do
        index = @errors.index { |error| error[:message].match?(pattern) }
        index ? !@errors.delete_at(index).nil? : false
      end
    end

    def record(details)
      return if IGNORED.any? { |matcher, _reason| matcher.call(details) }

      frame = details.dig("stackTrace", "callFrames")&.first
      entry = {
        message: message_of(details),
        text: details["text"],
        class_name: details.dig("exception", "className"),
        description: details.dig("exception", "description"),
        url: details["url"] || frame&.dig("url"),
        frame: frame && "#{frame['functionName'].presence || '(anonymous)'} #{frame['url']}:#{frame['lineNumber']}"
      }
      @lock.synchronize { @errors << entry }
    end
  end

  private

  def subscribe
    super
    on("Runtime.exceptionThrown") { |params| JsErrorCollector.record(params["exceptionDetails"]) }
  end
end
