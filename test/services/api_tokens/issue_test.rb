require "test_helper"

class ApiTokens::IssueTest < ActiveSupport::TestCase
  test "issues a token whose raw value authenticates" do
    result = ApiTokens::Issue.call(users(:one))
    token, raw = result.record
    assert result.ok?
    assert_equal token, ApiToken.authenticate(raw)
  end

  test "rotate revokes the user's active tokens first" do
    old, _ = ApiTokens::Issue.call(users(:one)).record
    ApiTokens::Issue.call(users(:one), rotate: true)
    assert old.reload.revoked_at.present?
  end

  test "revoke stops a token authenticating" do
    token, raw = ApiTokens::Issue.call(users(:one)).record
    assert ApiTokens::Revoke.call(token).ok?
    assert_nil ApiToken.authenticate(raw)
  end
end
