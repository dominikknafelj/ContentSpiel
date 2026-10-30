require "test_helper"

# An invited person is a `users` row in an invited state (spec "Invites";
# plan Rulings 2 and 3): the link's token is signed over `invite_sent_at`,
# so a resend kills the old link, a withdrawal (the row deleted) finds
# nothing, and an accepted invite still finds its row, which is no longer
# invited: "used".
class UserInviteTest < ActiveSupport::TestCase
  test "an invite link works for 7 days and dies on resend, on withdrawal and on acceptance (as used)" do
    user = invited_user("dana@example.com")
    token = user.generate_token_for(:invite)

    assert_equal user, User.find_by_token_for(:invite, token)
    assert_equal user.invite_sent_at + 7.days, user.invite_expires_at
    # In seconds: `travel(7.days)` adds calendar days in the machine's zone,
    # which across a change of clocks is an hour more or less than the
    # token's 168 hours.
    valid_for = User::INVITE_VALID_FOR.to_i.seconds
    travel(valid_for - 1.minute) { assert_equal user, User.find_by_token_for(:invite, token) }
    travel(valid_for + 1.minute) { assert_nil User.find_by_token_for(:invite, token) }

    # A resend moves invite_sent_at: the old link is dead, the new one works.
    travel(1.second) { user.update!(invite_sent_at: Time.current) }
    assert_nil User.find_by_token_for(:invite, token)
    resent = user.generate_token_for(:invite)
    assert_equal user, User.find_by_token_for(:invite, resent)

    # Accepting clears invited_at and keeps invite_sent_at: the link still
    # finds the row, which says it is used.
    user.update!(invited_at: nil)
    used = User.find_by_token_for(:invite, resent)
    assert_equal user, used
    assert_not used.invited?

    # A withdrawal deletes the row: nothing is found, which reads "expired".
    other = invited_user("eli@example.com")
    withdrawn = other.generate_token_for(:invite)
    other.destroy!
    assert_nil User.find_by_token_for(:invite, withdrawn)
    assert_nil User.find_by_token_for(:invite, "junk")
  end

  test "an invited row cannot sign in and is not can_sign_in" do
    user = invited_user("dana@example.com")

    assert user.invited?
    assert_includes User.invited, user
    assert_not_includes User.can_sign_in, user
    assert_includes User.can_sign_in, users(:one)
    assert_not_includes User.invited, users(:one)
    assert_nil User.new.invite_expires_at
  end

  # Plan Ruling 2: the digest is of a random password nobody is told.
  test "an invited row keeps a password digest, of a password nobody knows" do
    user = invited_user("dana@example.com")

    assert user.password_digest.present?
    assert_not user.authenticate("password")
    assert_not user.authenticate("")
  end
end
