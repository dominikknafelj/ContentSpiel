# The AI provider the system tests register as `test/gated`, in place of the
# two stubs that used to `sleep` on the server to keep a request in flight
# (a real-time delay is both slower than needed and, for an absence, a guess).
#
# The app server runs inside the test process, so a provider call is a real
# server thread. While the gate is HELD, `translate` and `test_connection`
# block on it; the test decides when they go on:
#
#   GatedProvider.hold!                    # from now on, calls wait
#   ...press the button...
#   assert_eventually { GatedProvider.waiting == 1 }   # the request is in flight
#   GatedProvider.release                  # the waiting ones answer, and later calls don't wait
#   GatedProvider.release(error: "…")      # ...they raise AI::Error with this message instead
#
# `served` counts the calls that have finished (answered or raised), which is
# the end of the window of a test that claims "a late answer changes nothing":
# wait for it, then assert.
#
# `release` opens the gate for good (until the next `hold!`): a test that
# presses Try again after releasing gets an immediate answer, not a second
# wait. `reset!` -- teardown, ALWAYS -- opens it, empties the counters and
# clears the error, so a test that failed with a request in flight never leaves
# a server thread waiting for the next test (or, with nobody to release it, for
# its own `HOLD_LIMIT`). The registry is per process, so parallel workers each
# have their own; `uninstall!` re-runs the `to_prepare` registrations, which
# reset the provider registry (and the block types) to their built-ins.
class GatedProvider
  NAME = "test/gated".freeze
  # What `test_connection` accepts; every other key is refused like the real
  # provider refuses a wrong one.
  VALID_KEY = "sk-ant-system-test-key".freeze
  # A held call that nobody releases gives up after this many seconds, with an
  # AI::Error, rather than hang the server thread.
  HOLD_LIMIT = 20

  @lock = Mutex.new
  @opened = ConditionVariable.new
  @held = false
  @error = nil
  @waiting = 0
  @served = 0
  @generation = 0

  class << self
    attr_reader :waiting, :served

    def install!
      reset!
      AI::Providers.register(NAME, self) unless AI::Providers.find(NAME) == self
    end

    def uninstall!
      reset!
      Rails.application.reloader.prepare!
    end

    def hold!
      @lock.synchronize { @held = true; @error = nil }
    end

    def release(error: nil)
      @lock.synchronize do
        @held = false
        @error = error
        @opened.broadcast
      end
    end

    def reset!
      @lock.synchronize do
        @held = false
        @error = nil
        @waiting = 0
        @served = 0
        @generation += 1
        @opened.broadcast
      end
    end

    # What `reset!` has been called for so far: a call that began before a
    # reset and ends after it must not count in the next test's `served`.
    attr_reader :generation

    # Called by the provider instance: blocks while the gate is held, then
    # answers the error the gate was released with (nil for none).
    def pass
      @lock.synchronize do
        @waiting += 1
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + HOLD_LIMIT
        generation = @generation
        while @held && generation == @generation
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break (@error = "The gate was never released.") if remaining <= 0

          @opened.wait(@lock, remaining)
        end
        @waiting -= 1 if generation == @generation
        generation == @generation ? @error : nil
      end
    end

    def finished!(generation) = @lock.synchronize { @served += 1 if generation == @generation }
  end

  def initialize(api_key:, model:)
    @api_key = api_key
    @generation = self.class.generation
  end

  # Answers `"[<to>] <text>"` for every text, and raises for any request
  # containing "boom" -- how a provider error during a bulk translation is
  # staged.
  def translate(texts:, from:, to:, format:)
    error = self.class.pass
    raise AI::Error, error if error
    raise AI::Error, "The AI provider is unavailable." if texts.any? { |text| text.to_s.downcase.include?("boom") }

    texts.map { |text| "[#{to}] #{text}" }
  ensure
    self.class.finished!(@generation)
  end

  def test_connection
    error = self.class.pass
    raise AI::Error, error if error
    raise AI::Error, "The AI provider refused the API key." unless @api_key == VALID_KEY

    true
  ensure
    self.class.finished!(@generation)
  end
end
