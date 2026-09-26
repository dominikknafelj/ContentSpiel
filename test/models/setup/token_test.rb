require "test_helper"

class Setup::TokenTest < ActiveSupport::TestCase
  teardown { ENV.delete("SETUP_TOKEN") }

  test "is derived from the app's secret: 24 hex characters, stable across calls" do
    assert_match(/\A\h{24}\z/, Setup::Token.value)
    assert_equal Setup::Token.value, Setup::Token.value
  end

  test "SETUP_TOKEN overrides the derived value" do
    ENV["SETUP_TOKEN"] = "chosen-by-the-operator"

    assert_equal "chosen-by-the-operator", Setup::Token.value
  end

  test "accepts the token with whitespace copied from a log line" do
    assert Setup::Token.valid?("  #{Setup::Token.value}\n")
  end

  test "rejects a wrong, empty, or missing token" do
    assert_not Setup::Token.valid?("0" * 24)
    assert_not Setup::Token.valid?("")
    assert_not Setup::Token.valid?(nil)
  end
end
