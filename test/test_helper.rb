ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/setup_test_helper"
require_relative "test_helpers/turbo_stream_test_helper"
require_relative "support/content_helper"
require_relative "support/component_test_helper"
require_relative "support/test_types"

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

    # Add more helper methods to be used by all tests here...
  end
end
