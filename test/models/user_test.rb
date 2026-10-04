require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "email address is required and unique" do
    User.create!(email_address: "taken@example.com", password: "password12345")

    assert_not User.new(email_address: "", password: "password12345").valid?
    assert_not User.new(email_address: "TAKEN@example.com", password: "password12345").valid?
  end

  # users(:one) is the sole owner in fixtures (test/fixtures/users.yml);
  # every other fixture user, including :two, isn't an owner at all, so
  # none of them can trip this guard.
  test "the last owner can't be destroyed" do
    last = users(:one)

    assert_not last.destroy
    assert_includes last.errors.full_messages, "The last owner can't be deleted"
    assert User.exists?(last.id)
  end

  test "a non-owner can always be destroyed" do
    assert users(:two).destroy
    assert_not User.exists?(users(:two).id)
  end

  test "a second owner allows destroying the first" do
    User.create!(email_address: "owner2@example.com", password: "password12345", owner: true)

    assert users(:one).destroy
    assert_not User.exists?(users(:one).id)
  end

  test "the last owner can't be demoted" do
    last = users(:one)

    assert_not last.update(owner: false)
    assert_includes last.errors[:owner], "can't demote the last owner"
    assert last.reload.owner?
  end

  test "a second owner allows demoting the first" do
    User.create!(email_address: "owner2@example.com", password: "password12345", owner: true)

    assert users(:one).update(owner: false)
    assert_not users(:one).reload.owner?
  end

  test "demoting a non-owner is unaffected by the owner guard" do
    assert users(:two).update(owner: false)
  end

  test "promoting a user to owner needs no other owner to exist" do
    assert users(:two).update(owner: true)
  end

  # Final fix wave (C, P16), carried over by the access-control migration
  # (Task 2): the last-owner check runs *before* the dependent destroys (so
  # a refused delete never even starts deleting sessions/tokens), and
  # counts under a row lock, so two admins destroying/demoting the last two
  # owners at the same moment can't both see "one other owner left" and
  # both succeed.
  test "destroying the last owner is refused before dependent sessions are destroyed" do
    last = users(:one)
    last.sessions.create!

    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| statements << payload[:sql] }
    begin
      assert_not last.destroy
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert_not statements.any? { |sql| sql.match?(/DELETE FROM "sessions"/) }, "dependent sessions were deleted before the check refused"
  end

  test "the last-owner check counts owners under a row lock" do
    assert_queries_match(/FOR UPDATE/) { users(:one).destroy }
  end

  test "display_name is the name, or the email when there is none" do
    user = users(:one)
    user.name = nil
    assert_equal user.email_address, user.display_name
    user.name = "   "
    assert_equal user.email_address, user.display_name
    user.name = " Ada Lovelace "
    assert_equal "Ada Lovelace", user.display_name
  end

  test "name is optional and capped at 120 characters" do
    user = users(:one)
    user.name = "a" * 121
    assert_not user.valid?
    user.name = ""
    assert user.valid?
    assert_nil user.name, "a blank name is stored as nil"
  end

  test "a new password needs at least 12 characters" do
    user = users(:one)
    user.password = user.password_confirmation = "elevenchars"
    assert_not user.valid?
    assert_equal [ "Use at least 12 characters." ], user.errors[:password]
    assert_includes user.errors.full_messages, "Use at least 12 characters.", "the rule's message reads the same everywhere, with no attribute prefix"
    user.password = user.password_confirmation = "twelve chars"
    assert user.valid?
  end

  test "twelve multibyte characters are enough: the rule counts characters, not bytes" do
    user = users(:one)
    user.password = user.password_confirmation = "üüüüüüüüüüüü"
    assert user.valid?
  end

  test "a user whose stored password is shorter still authenticates and saves other changes" do
    user = users(:one) # fixture digest is for "password"
    assert user.authenticate("password")
    assert user.update(name: "Unchanged password")
  end

  test "the other password messages keep their attribute prefix" do
    user = User.new(email_address: "blank@example.com")
    assert_not user.valid?
    assert_includes user.errors.full_messages, "Password can't be blank"
  end
end
