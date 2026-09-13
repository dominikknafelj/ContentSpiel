require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "generate! returns a persisted token and the raw value" do
    token, raw = ApiToken.generate!

    assert token.persisted?
    assert_not_nil raw
    assert_not_equal raw, token.token_digest
  end

  test "authenticate finds the token matching the raw value" do
    token, raw = ApiToken.generate!

    assert_equal token, ApiToken.authenticate(raw)
  end

  test "authenticate returns nil for a wrong value" do
    ApiToken.generate!

    assert_nil ApiToken.authenticate("wrong-token")
  end

  test "revoked tokens do not authenticate" do
    token, raw = ApiToken.generate!
    token.revoke!

    assert_nil ApiToken.authenticate(raw)
  end
end
