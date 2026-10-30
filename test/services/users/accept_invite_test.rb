require "test_helper"

# `Users::AcceptInvite` (design answer M5): the invited person sets a password
# through the link. The token is the credential, so nobody is signed in when
# it runs, and the event is the invited person's own.
class Users::AcceptInviteTest < ActiveSupport::TestCase
  setup do
    @invited = invited_user("dana@example.com", name: "Dana")
    @token = @invited.generate_token_for(:invite)
  end

  def accept(token = @token, name: "Dana Example", password: "a-long-password-1", password_confirmation: password)
    as(nil) { Users::AcceptInvite.call(token:, name:, password:, password_confirmation:) }
  end

  test "sets the password and name, clears invited_at, records user.invite_accepted as the invited user, and answers used for a second press" do
    result = accept

    assert result.ok?, result.errors.inspect
    user = result.record.reload
    assert_equal @invited, user
    assert_not user.invited?
    assert_includes User.can_sign_in, user
    assert user.authenticate("a-long-password-1")
    assert_equal "Dana Example", user.name

    event = Audit::Event.find_by!(action: "user.invite_accepted")
    assert_equal [ user, user.id ], [ event.subject, event.user_id ]
    assert_equal [ nil, "password changed" ], event.field_changes["credentials"]
    assert_empty event.metadata
    assert_not_includes event.attributes.to_json, "a-long-password-1"

    second = accept(password: "another-long-password")
    assert_not second.ok?
    assert_equal [ :used ], second.errors
    assert_equal user, second.record
    assert user.reload.authenticate("a-long-password-1")
    assert_equal 1, Audit::Event.where(action: "user.invite_accepted").count
  end

  # One answer for all three, so the page does not say whether an invite
  # existed (M5).
  test "an expired, a resent, a withdrawn and a junk link are all expired, and write nothing" do
    travel(User::INVITE_VALID_FOR.to_i.seconds + 1.minute) { assert_equal [ :expired ], accept.errors }

    resent = invited_user("eli@example.com")
    old = resent.generate_token_for(:invite)
    travel(1.second) { resent.update!(invite_sent_at: Time.current) }
    assert_equal [ :expired ], accept(old).errors

    withdrawn = invited_user("fay@example.com")
    gone = withdrawn.generate_token_for(:invite)
    withdrawn.destroy!
    assert_equal [ :expired ], accept(gone).errors

    assert_equal [ :expired ], accept("junk").errors
    assert_equal [ :expired ], accept(nil).errors
    assert_nil accept("junk").record

    assert @invited.reload.invited?
    assert_empty Audit::Event.all
  end

  test "a password that is blank, short or unconfirmed is refused and the invite stays open" do
    results = [
      accept(password: "", password_confirmation: ""), accept(password: "short"),
      accept(password: "a-long-password-1", password_confirmation: "another-password"),
      accept(password: "a-long-password-1", password_confirmation: ""), accept(name: "x" * 121)
    ]
    assert_includes results[0].errors, "Password can't be blank"
    assert_includes results[1].errors, "Use at least 12 characters."
    results.each do |result|
      assert_not result.ok?
      # The record handed back, not only the row: the page shows the form
      # again on it, and "used" only for a row that is no longer invited.
      assert result.record.invited?, "#{result.errors.inspect}: the returned record says it is no longer invited"
    end

    assert @invited.reload.invited?
    assert_equal "Dana", @invited.name
    assert_empty Audit::Event.all
  end

  # A signed-in session in the same browser is not who accepts: the token is.
  test "whoever is signed in, the acceptance is the invited person's" do
    result = as(users(:one)) { Users::AcceptInvite.call(token: @token, name: "", password: "a-long-password-1", password_confirmation: "a-long-password-1") }

    assert result.ok?
    assert_nil @invited.reload.name
    assert_equal @invited.id, Audit::Event.find_by!(action: "user.invite_accepted").user_id
  end
end
