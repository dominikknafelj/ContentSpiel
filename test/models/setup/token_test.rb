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

  test "the boot's line names the derived token, which a person can read nowhere else" do
    assert_equal "[ContentSpiel] Setup is not complete. Open /setup and enter this setup token: #{Setup::Token.value}",
      Setup::Token.log_line
  end

  # The operator chose it and knows it: the log has no reason to repeat a
  # value that is a secret until setup is done.
  test "with SETUP_TOKEN set the boot's line names the variable and holds no token" do
    ENV["SETUP_TOKEN"] = "chosen-by-the-operator"

    assert_equal "[ContentSpiel] Setup is not complete. Open /setup and enter the setup token you set in SETUP_TOKEN.",
      Setup::Token.log_line
    assert_not_includes Setup::Token.log_line, "chosen-by-the-operator"
  end

  test "a blank SETUP_TOKEN is no token of the operator's: the line names the derived one" do
    ENV["SETUP_TOKEN"] = "  "

    assert_includes Setup::Token.log_line, Setup::Token.value
    assert_match(/\h{24}\z/, Setup::Token.log_line)
  end

  test "the initializer logs the line and builds none of its own" do
    source = Rails.root.join("config/initializers/setup_token.rb").read

    assert_includes source, "Rails.logger.warn Setup::Token.log_line"
    assert_not_includes source, "Setup::Token.value"
  end
end
