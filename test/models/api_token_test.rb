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
    assert_not_equal raw, token.lookup_digest
    assert_equal ApiToken.digest(raw), token.lookup_digest
  end

  test "authenticate finds the token matching the raw value" do
    token, raw = ApiToken.generate!(@user)

    assert_equal token, ApiToken.authenticate(raw)
  end

  test "authenticate finds nothing for a blank or missing value, without a query" do
    ApiToken.generate!(@user)

    assert_equal 0, count_queries {
      assert_nil ApiToken.authenticate("")
      assert_nil ApiToken.authenticate("   ")
      assert_nil ApiToken.authenticate(nil)
    }
  end

  test "authenticate does not raise on a string with invalid bytes" do
    assert_nil ApiToken.authenticate("\xFF".dup.force_encoding("UTF-8"))
  end

  test "a token differing in its last character is refused" do
    _, raw = ApiToken.generate!(@user)

    assert_nil ApiToken.authenticate(raw[0..-2] + (raw[-1] == "0" ? "1" : "0"))
  end

  test "the migration's placeholder can never be a digest: a real digest is 64 hex characters" do
    token, raw = ApiToken.generate!(@user)

    assert_match(/\A\h{64}\z/, ApiToken.digest(raw))
    assert_no_match(/\A\h{64}\z/, "revoked:#{token.id}")
  end

  test "two tokens never share a digest, and the database refuses a second row with one" do
    first, = ApiToken.generate!(@user)
    second, = ApiToken.generate!(@user)
    assert_not_equal first.lookup_digest, second.lookup_digest

    assert_raises(ActiveRecord::RecordNotUnique) do
      ApiToken.new(user: @user, group: first.group, name: "Dup", lookup_digest: first.lookup_digest).save!(validate: false)
    end
  end

  test "the lookup digest is masked when a token is inspected" do
    assert_not_includes ApiToken.new(lookup_digest: "visible-value").inspect, "visible-value"
  end

  test "authenticating is one indexed equality lookup that loads one row, however many tokens exist" do
    token, raw = ApiToken.generate!(@user)
    sql = []
    loaded = 0
    queries = ->(*, payload) { sql << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    rows = ->(*, payload) { loaded += payload[:record_count] }
    run = lambda do
      sql.clear
      loaded = 0
      ActiveSupport::Notifications.subscribed(queries, "sql.active_record") do
        ActiveSupport::Notifications.subscribed(rows, "instantiation.active_record") { assert_equal token, ApiToken.authenticate(raw) }
      end
    end

    run.call
    assert_equal [ 1, 1 ], [ sql.size, loaded ]
    assert_match(/"lookup_digest" = \$1.*LIMIT/m, sql.first)

    30.times { |i| ApiToken.generate!(User.create!(email_address: "bulk#{i}@example.com", password: "password12345")) }
    run.call
    assert_equal [ 1, 1 ], [ sql.size, loaded ]
    assert_match(/"lookup_digest" = \$1.*LIMIT/m, sql.first)
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
    token = ApiToken.new(lookup_digest: "x")

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
      ApiToken.new(user: @user, group:, name: "CLAUDE", lookup_digest: "x1").save!(validate: false)
    end
  end

  test "the index lets a name be used again once the first token is revoked" do
    first, = ApiToken.generate!(@user, name: "Claude")
    first.revoke!
    ApiToken.new(user: @user, group: first.group, name: "Claude", lookup_digest: "x2").save!(validate: false)
    assert_equal 2, ApiToken.where(user: @user, name: "Claude").count
  end

  # Final fix wave (Task 2): only the race the retry exists for is retried --
  # a clash on the generated NAME. Anything else wrong with the row would fail
  # the same way five times over, and hide behind the retries.
  test "a generated name is not retried for a failure that isn't about the name" do
    calls = 0
    original = ApiToken.method(:next_default_name)
    ApiToken.define_singleton_method(:next_default_name) do |user|
      calls += 1
      original.call(user)
    end

    error = assert_raises(ActiveRecord::RecordInvalid) { ApiToken.generate!(@user, group: nil) }
    assert_empty error.record.errors[:name]
    assert_equal 1, calls
  ensure
    ApiToken.singleton_class.send(:remove_method, :next_default_name)
    ApiToken.define_singleton_method(:next_default_name, original)
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

  private

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
