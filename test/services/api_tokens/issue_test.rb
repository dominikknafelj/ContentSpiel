require "test_helper"

class ApiTokens::IssueTest < ActiveSupport::TestCase
  test "issues a token whose raw value authenticates" do
    result = ApiTokens::Issue.call(users(:one))
    token, raw = result.record
    assert result.ok?
    assert_equal token, ApiToken.authenticate(raw)
  end

  test "issuing again adds another active token rather than replacing the old one" do
    old, old_raw = ApiTokens::Issue.call(users(:one)).record
    ApiTokens::Issue.call(users(:one))
    assert_nil old.reload.revoked_at
    assert_equal old, ApiToken.authenticate(old_raw)
  end

  test "revoke stops a token authenticating" do
    token, raw = ApiTokens::Issue.call(users(:one)).record
    assert ApiTokens::Revoke.call(token).ok?
    assert_nil ApiToken.authenticate(raw)
  end
end
