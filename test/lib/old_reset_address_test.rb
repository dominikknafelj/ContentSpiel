require "test_helper"

# The middleware at the door (lib/old_reset_address.rb): the token of an old
# reset address is replaced in every place Rack and Rails keep a request's
# address, before the application is called. The requests themselves, with
# what they log, are in test/controllers/admin/passwords_controller_test.rb;
# this is the table of keys, two of which (`REQUEST_URI`, `REQUEST_PATH`)
# only a real web server sets.
class OldResetAddressTest < ActiveSupport::TestCase
  ADMIN = "/#{ContentSpiel::ADMIN_PATH}".freeze
  WORD = "not-a-real-token-0123456789".freeze

  def env_after(env)
    seen = nil
    status, = OldResetAddress.new(->(inner) { seen = inner.dup; [ 204, {}, [] ] }).call(env)
    assert_equal 204, status
    seen
  end

  test "every key that holds the address is rewritten before the application is called, and nothing else" do
    seen = env_after(
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "#{ADMIN}/password/#{WORD}/edit",
      "ORIGINAL_FULLPATH" => "#{ADMIN}/password/#{WORD}/edit?from=mail",
      "REQUEST_URI" => "http://example.org#{ADMIN}/password/#{WORD}/edit?from=mail",
      "REQUEST_PATH" => "#{ADMIN}/password/#{WORD}/edit",
      "QUERY_STRING" => "from=mail",
      "HTTP_X_OTHER" => "#{ADMIN}/password/#{WORD}/edit"
    )

    assert_equal "#{ADMIN}/password/[FILTERED]/edit", seen["PATH_INFO"]
    assert_equal "#{ADMIN}/password/[FILTERED]/edit?from=mail", seen["ORIGINAL_FULLPATH"]
    assert_equal "http://example.org#{ADMIN}/password/[FILTERED]/edit?from=mail", seen["REQUEST_URI"]
    assert_equal "#{ADMIN}/password/[FILTERED]/edit", seen["REQUEST_PATH"]
    assert_equal "from=mail", seen["QUERY_STRING"]
    assert_equal "#{ADMIN}/password/#{WORD}/edit", seen["HTTP_X_OTHER"], "only the address's own keys"
    assert_equal OldResetAddress::KEYS.sort, seen.select { |_, value| value.to_s.include?("[FILTERED]") }.keys.sort
  end

  test "the old form's address is rewritten too" do
    assert_equal "#{ADMIN}/password/[FILTERED]", env_after("PATH_INFO" => "#{ADMIN}/password/#{WORD}")["PATH_INFO"]
  end

  test "the form's addresses as they are now, any other address and a request with no path pass as they came" do
    [ "#{ADMIN}/password/edit", "#{ADMIN}/password/new", "#{ADMIN}/password", "#{ADMIN}/account/password", "/", "/en/blog/password/x/edit" ].each do |path|
      env = { "PATH_INFO" => path, "ORIGINAL_FULLPATH" => path }
      assert_equal env, env_after(env.dup), path
    end
    assert_equal({}, env_after({}))
  end

  # Ahead of everything of Rails that reads a request's address: the logger
  # of the first line and the two that log an error (named below; whatever
  # else there is, host authorisation in production, is behind it too). The
  # one middleware that may stand before it is OpenTelemetry's
  # (`Rack::Events`, which puts itself first where telemetry is on); what it
  # writes into a span goes through `Telemetry::PathScrubber` on its own.
  test "it stands ahead of every middleware of Rails, the request logger and the error pages among them" do
    stack = Rails.application.middleware.map(&:klass)
    door = stack.index(OldResetAddress)

    assert door, "OldResetAddress is not in the stack"
    assert_empty stack.first(door) - [ Rack::Events ]
    [ Rails::Rack::Logger, ActionDispatch::ShowExceptions, ActionDispatch::DebugExceptions ].each do |later|
      assert_operator door, :<, stack.index(later), later.name
    end
  end
end
