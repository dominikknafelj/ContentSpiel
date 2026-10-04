ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/setup_test_helper"
require_relative "test_helpers/turbo_stream_test_helper"
require_relative "support/content_helper"
require_relative "support/component_test_helper"
require_relative "support/test_types"

# What tests themselves print -- the statements a migration test runs
# ("-- execute(...)"), the seed file's "Seeded dev accounts" lines -- is noise
# between the dots that makes a real failure harder to spot, so a local run
# keeps it quiet. `VERBOSE=1 bin/rails test` shows it all, and CI always runs
# that way (`.github/workflows/ci.yml`), so a log there is complete.
module TestOutput
  def self.verbose? = ENV["VERBOSE"].present? && ENV["VERBOSE"] != "0"

  # Runs the block with standard output swallowed, unless verbose. The stream
  # is restored even if the block raises, and what a failing block printed is
  # shown after all: it is usually the explanation.
  def self.quietly
    return yield if verbose?

    original = $stdout
    captured = StringIO.new
    $stdout = captured
    yield
  rescue Exception # rubocop:disable Lint/RescueException -- re-raised below; only here to show the captured output first
    original&.print(captured&.string)
    raise
  ensure
    $stdout = original if original
  end
end

ActiveRecord::Migration.verbose = TestOutput.verbose?

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Builds pages/posts through the write-path services (spec §11) instead
    # of fixtures -- see test/support/content_helper.rb.
    include ContentHelper

    # Setup.required? memoizes "setup is done" per process (spec §6.1), reset
    # by SiteSetting after every commit -- but a test that clears the table
    # with `delete_all`/`destroy_all` bypasses callbacks entirely, and the
    # memo would otherwise leak a stale "done" from whichever earlier test in
    # this worker last completed setup. Resetting before every test, the way
    # the spec calls for, keeps that leak from ever being observable.
    setup { Setup.reset! }

    # Runs the block as `actor` (a User or ApiToken) on `channel`, the way
    # a CS Studio request would (access-control design spec §3.3) -- so a
    # service called inside it is authorized and audited for that actor.
    # Outside one, tests run with a nil actor and nil channel, which the
    # checker trusts like the console; tests about permissions say who's
    # acting explicitly instead of leaning on that.
    def as(actor, channel: :admin, &block)
      Current.set(actor: actor, channel: channel, &block)
    end

    def as_owner(&block) = as(users(:one), &block)

    # Replaces a singleton method (a module function, a class method) for
    # the block's duration, then restores it -- for forcing a failure out of
    # a collaborator the code under test calls.
    def with_singleton_override(object, name, implementation)
      original = object.method(name)
      object.define_singleton_method(name, &implementation)
      yield
    ensure
      object.define_singleton_method(name, original)
    end
  end
end
