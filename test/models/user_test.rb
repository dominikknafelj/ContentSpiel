require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "email address is required and unique" do
    User.create!(email_address: "taken@example.com", password: "password123")

    assert_not User.new(email_address: "", password: "password123").valid?
    assert_not User.new(email_address: "TAKEN@example.com", password: "password123").valid?
  end

  test "the last user can't be destroyed" do
    users(:two).destroy!
    last = users(:one)

    assert_not last.destroy
    assert_includes last.errors.full_messages, "The last user can't be deleted"
    assert User.exists?(last.id)
  end

  test "a user can be destroyed when another remains" do
    assert users(:two).destroy
    assert_not User.exists?(users(:two).id)
  end

  # Final fix wave (C, P16): the last-user check runs *before* the
  # dependent destroys (so a refused delete never even starts deleting
  # sessions/tokens), and counts under a row lock, so two admins deleting
  # the two remaining users at the same moment can't both see "one other
  # user left" and both succeed.
  test "the last-user check runs first and counts under a row lock" do
    users(:two).destroy!
    last = users(:one)
    last.sessions.create!

    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| statements << payload[:sql] }
    begin
      assert_not last.destroy
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert statements.any? { |sql| sql.include?(%(FROM "users")) && sql.include?("FOR UPDATE") }, statements.join("\n")
    assert_not statements.any? { |sql| sql.match?(/DELETE FROM "sessions"/) }, "dependent sessions were deleted before the check refused"
  end
end
