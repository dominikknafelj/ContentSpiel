ENV["RAILS_ENV"] ||= "test"

# Code coverage, on request: `COVERAGE=1 bin/rails test` writes
# coverage/index.html (`bundle exec simplecov open` shows it). It has to start
# before any application code is loaded, hence here, above the environment.
# Off by default: a run of one file would report a meaningless few percent
# after every run, and coverage slows the suite down a little. CI turns it on
# for the unit suite and keeps the report as an artifact.
if ENV["COVERAGE"].present? && ENV["COVERAGE"] != "0"
  require "simplecov"
  SimpleCov.start "rails" do
    enable_coverage :branch
    group "Components", "app/components"
    group "Services", "app/services"
    group "Queries", "app/queries"
    group "MCP", "app/mcp"
  end
end

# THE SUITE DOES NOT DEPEND ON THE SHELL'S SITE ADDRESS. Someone who has
# `PUBLIC_HOST` exported, as the hosting documents tell a person to try
# locally, would otherwise run every test under that address:
# head tags, the sitemap and MCP's URLs carry it, and five tests that expect
# "no address configured" failed that way. Removed here, once, before the
# application is loaded and so before anything can read or memoise the
# address; parallel workers fork after this and inherit it. A test that wants
# an address sets one with `with_site_address` (test/support/site_address_helper.rb).
# THEME_PATH goes the same way: `ThemeFolder` ignores it under test anyway,
# and a child process a test starts (test/lib/production_boot_test.rb) must
# get the theme the test names and not the shell's. The mail variables go too
# (`MailSettings::ENV_NAMES`): a developer's MAIL_SMTP_SERVER would otherwise
# point every test's mail at a real server. The Turnstile keys and
# LEAKED_PASSWORD_CHECK go too, so a test has a bot check only inside
# `with_bot_check` and a leaked-password check only inside
# `with_leaked_password_check`, neither of which asks the network
# (test/support/sign_in_helper.rb).
%w[PUBLIC_HOST THEME_PATH
   MAIL_SMTP_SERVER MAIL_SMTP_PORT MAIL_SMTP_SECURITY MAIL_SMTP_USERNAME MAIL_SMTP_PASSWORD
   MAIL_SENDER_NAME MAIL_SENDER_ADDRESS
   TURNSTILE_SITE_KEY TURNSTILE_SECRET_KEY LEAKED_PASSWORD_CHECK].each { |name| ENV.delete(name) }

require_relative "../config/environment"
SiteAddress.reset!
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/setup_test_helper"
require_relative "test_helpers/turbo_stream_test_helper"
require_relative "support/content_helper"
require_relative "support/component_test_helper"
require_relative "support/test_types"
require_relative "support/gallery_album"
require_relative "support/block_samples"
require_relative "support/ui_contract"
require_relative "support/design_system_entries"
require_relative "support/built_in_block_types"
require_relative "support/contract_ledger"
require_relative "support/site_address_helper"
require_relative "support/media_renditions"
require_relative "support/mail_state"
require_relative "support/mail_button"
require_relative "support/invites"
require_relative "support/smtp_stub"
require_relative "support/encryption_keys"
require_relative "support/form_sends"
require_relative "support/log_capture"
require_relative "support/sanitizer_parses"
require_relative "support/contrast_measure"
require_relative "support/theme_test_helper"
require_relative "support/sign_in_helper"

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

    # Each parallel worker is a fork with its own coverage data: give each
    # its own name so the results are merged into one report instead of the
    # last worker's overwriting the others'.
    if defined?(SimpleCov)
      parallelize_setup { |worker| SimpleCov.command_name "#{SimpleCov.command_name}-#{worker}" }
      parallelize_teardown { SimpleCov.result }
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical
    # order. `test/fixtures/themes` holds theme folders, whose theme.yml is a
    # theme's declarations and no fixture set: `fixtures :all` would read it
    # as one and fail.
    fixtures(*Dir[Rails.root.join("test/fixtures/**/*.yml")].map { |file| file.delete_prefix("#{Rails.root.join("test/fixtures")}/").delete_suffix(".yml") }.reject { |name| name.start_with?("themes/") }.sort)

    # Builds pages/posts through the write-path services instead of
    # fixtures -- see test/support/content_helper.rb.
    include ContentHelper

    # `sample_block`, `sample_every_type`, `assert_every_type_built`: one
    # block of a type from its declared sample -- see
    # test/support/block_samples.rb.
    include BlockSamples

    # `with_site_address(value) { ... }`: PUBLIC_HOST for a block, with
    # `SiteAddress`'s memo dropped on both sides -- see
    # test/support/site_address_helper.rb.
    include SiteAddressHelper
    # `make_renditions!(asset)`: a recorded generation, no file made -- see
    # test/support/media_renditions.rb.
    include MediaRenditions
    include MailState
    # `open_invitation(email)`: an open invitation -- see
    # test/support/invites.rb.
    include Invites
    # `without_encryption_keys { ... }`: a site with no Active Record
    # encryption keys -- see test/support/encryption_keys.rb.
    include EncryptionKeys
    # `aged_drawn(form)`, `clear_form_send_limits`, `place_form(page, form)`:
    # a visitor's send -- see test/support/form_sends.rb.
    include FormSends

    # `with_plain_theme { ... }`: the second theme for a block -- see
    # test/support/theme_test_helper.rb.
    include ThemeTestHelper

    # `with_bot_check(answer) { ... }`, `with_leaked_password_check { ... }`
    # and `with_http_stub { |url, requests| ... }`:
    # the sign-in checks' outside calls, never the network -- see
    # test/support/sign_in_helper.rb.
    include SignInHelper

    # Setup.required? memoizes "setup is done" per process, reset by
    # SiteSetting after every commit -- but a test that clears the table with
    # `delete_all`/`destroy_all` bypasses callbacks entirely, and the memo
    # would otherwise leak a stale "done" from whichever earlier test in this
    # worker last completed setup. Resetting before every test keeps that leak
    # from ever being observable.
    setup { Setup.reset! }

    # The throttle's counters live in one memory store of the process in this
    # environment (`SignIn.store`), so a test's failures would close the next
    # test's buckets.
    setup { SignIn.store.clear }

    # Runs the block as `actor` (a User or ApiToken) on `channel`, the way a
    # CS Studio request would -- so a service called inside it is authorized
    # and audited for that actor.
    # Outside one, tests run with a nil actor and nil channel, which the
    # checker trusts like the console; tests about permissions say who's
    # acting explicitly instead of leaning on that.
    def as(actor, channel: :admin, &block)
      Current.set(actor: actor, channel: channel, &block)
    end

    def as_owner(&block) = as(users(:one), &block)

    # Every SQL statement the block runs, in order -- for a test that says
    # "this write doesn't touch that table" or "this costs the same at any
    # size". Schema lookups are left out (they depend on what is cached).
    def capture_sql
      statements = []
      callback = ->(*, payload) { statements << payload[:sql] unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
      statements
    end

    # How many statements the block runs, cached ones included (a statement
    # per row shows up either way): the count a "costs the same for 3 as for
    # 30" test compares.
    def count_statements(&) = capture_sql(&).size

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
