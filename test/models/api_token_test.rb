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

  test "generate! without a name picks the next free Token N for that user" do
    first, = ApiToken.generate!(@user)
    second, = ApiToken.generate!(@user)
    other, = ApiToken.generate!(users(:one))

    assert_equal "Token 1", first.name
    assert_equal "Token 2", second.name
    assert_equal "Token 1", other.name
  end

  test "a name is stripped, required and at most 60 characters" do
    assert_equal "Claude", ApiToken.generate!(@user, name: "  Claude  ").first.name
    assert_raises(ActiveRecord::RecordInvalid) { ApiToken.generate!(@user, name: "") }
    assert_raises(ActiveRecord::RecordInvalid) { ApiToken.generate!(@user, name: "   ") }
    assert ApiToken.generate!(@user, name: "n" * 60).first.persisted?
    assert_raises(ActiveRecord::RecordInvalid) { ApiToken.generate!(@user, name: "n" * 61) }
  end

  test "a name is unique among the user's active tokens, case-insensitively" do
    first, = ApiToken.generate!(@user, name: "Claude")
    error = assert_raises(ActiveRecord::RecordInvalid) { ApiToken.generate!(@user, name: "claude") }
    assert_includes error.record.errors[:name], "is already the name of one of this user's active tokens"

    first.revoke!
    assert ApiToken.generate!(@user, name: "claude").first.persisted?, "a revoked token's name is free again"
    assert ApiToken.generate!(users(:one), name: "claude").first.persisted?, "another user's token may share a name"
  end

  test "a revoked token stays valid when a newer active token holds its name" do
    old, = ApiToken.generate!(@user, name: "Claude")
    old.revoke!
    ApiToken.generate!(@user, name: "Claude")
    assert old.reload.valid?
  end

  test "the database refuses a second active token with the same name, whatever the case" do
    ApiToken.generate!(@user, name: "Claude")
    group = access_control_groups(:admin)
    assert_raises(ActiveRecord::RecordNotUnique) do
      ApiToken.new(user: @user, group:, name: "CLAUDE", token_digest: "x").save!(validate: false)
    end
  end

  test "the index lets a name be used again once the first token is revoked" do
    first, = ApiToken.generate!(@user, name: "Claude")
    first.revoke!
    ApiToken.new(user: @user, group: first.group, name: "Claude", token_digest: "x").save!(validate: false)
    assert_equal 2, ApiToken.where(user: @user, name: "Claude").count
  end

  test "a generated name retries with the next number when it loses the race" do
    calls = 0
    original = ApiToken.method(:next_default_name)
    ApiToken.define_singleton_method(:next_default_name) do |user|
      calls += 1
      # First look returns a name that an active token already holds (as if
      # taken between the look and the insert), the second is honest.
      calls == 1 ? "Token 1" : original.call(user)
    end
    ApiToken.generate!(@user, name: "Token 1")
    token, = ApiToken.generate!(@user)
    assert_equal "Token 2", token.name
    assert_equal 2, calls
  ensure
    ApiToken.singleton_class.send(:remove_method, :next_default_name)
    ApiToken.define_singleton_method(:next_default_name, original)
  end
end
