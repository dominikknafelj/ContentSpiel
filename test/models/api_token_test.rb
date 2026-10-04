require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "agent@example.com", password: "password12345")
  end

  test "generate! returns a persisted token bound to the given user, and the raw value" do
    token, raw = ApiToken.generate!(@user)

    assert token.persisted?
    assert_equal @user, token.user
    assert_not_nil raw
    assert_not_equal raw, token.token_digest
  end

  test "authenticate finds the token matching the raw value" do
    token, raw = ApiToken.generate!(@user)

    assert_equal token, ApiToken.authenticate(raw)
  end

  test "authenticate returns nil for a wrong value" do
    ApiToken.generate!(@user)

    assert_nil ApiToken.authenticate("wrong-token")
  end

  test "revoked tokens do not authenticate" do
    token, raw = ApiToken.generate!(@user)
    token.revoke!

    assert_nil ApiToken.authenticate(raw)
  end

  # Mirrors Session's own ip_address tracking -- visibility into a bearer
  # credential used unattended by an MCP client, not just at creation.
  test "record_usage! stamps last_used_at and last_used_ip" do
    token, = ApiToken.generate!(@user)

    travel_to Time.current do
      token.record_usage!("203.0.113.5")

      assert_equal Time.current, token.reload.last_used_at
      assert_equal "203.0.113.5", token.last_used_ip
    end
  end

  test "a token requires a user" do
    token = ApiToken.new(token_digest: "x")

    assert_not token.valid?
    assert_includes token.errors[:user], "must exist"
  end

  test "destroying a user destroys their tokens" do
    ApiToken.generate!(@user)

    assert_difference "ApiToken.count", -1 do
      @user.destroy!
    end
  end
end
