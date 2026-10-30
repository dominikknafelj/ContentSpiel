require "test_helper"

# `Invitations::Accept` (design answer M5): the invited person sets a
# password through the link, and the account is made then. The token is the
# credential, so nobody is signed in when it runs, and the event is the new
# account's own.
class Invitations::AcceptTest < ActiveSupport::TestCase
  setup do
    @invitation = open_invitation("dana@example.com", name: "Dana", groups: [ access_control_groups(:read_only) ])
    @token = @invitation.generate_token_for(:accept)
  end

  def accept(token = @token, name: "Dana Example", password: "a-long-password-1", password_confirmation: password)
    as(nil) { Invitations::Accept.call(token:, name:, password:, password_confirmation:) }
  end

  test "creates the account in the invitation's groups, marks it accepted, records invitation.accepted as the new user, and answers used for a second press" do
    result = nil
    assert_difference -> { User.count }, 1 do
      result = accept
    end

    assert result.ok?, result.errors.inspect
    user = result.record
    assert_equal [ "dana@example.com", "Dana Example" ], [ user.email_address, user.name ]
    assert user.authenticate("a-long-password-1")
    assert_equal [ access_control_groups(:read_only) ], user.groups.to_a
    assert_not user.owner?
    @invitation.reload
    assert @invitation.accepted?
    assert_equal user, @invitation.user

    event = Audit::Event.find_by!(action: "invitation.accepted")
    assert_equal [ user, user.id ], [ event.subject, event.user_id ]
    assert_equal({ "invitation_id" => @invitation.id }, event.metadata)
    assert_equal [ [], [ access_control_groups(:read_only).id ] ], event.field_changes["group_ids"]
    assert_not_includes event.attributes.to_json, "a-long-password-1"
    assert_not_includes event.attributes.to_json, "password_digest"
    assert_not_includes event.attributes.to_json, @token

    second = accept(password: "another-long-password")
    assert_not second.ok?
    assert_equal [ :used ], second.errors
    assert_equal @invitation, second.record
    assert user.reload.authenticate("a-long-password-1")
    assert_equal 1, Audit::Event.where(action: "invitation.accepted").count
  end

  # One answer for all of them, so the page does not say whether an
  # invitation existed (M5).
  test "an expired, a resent, a withdrawn and a junk link are all expired, and write nothing" do
    travel(Invitation::VALID_FOR.to_i.seconds + 1.minute) { assert_equal [ :expired ], accept.errors }

    resent = open_invitation("eli@example.com")
    old = resent.generate_token_for(:accept)
    travel(1.second) { resent.update!(sent_at: Time.current) }
    assert_equal [ :expired ], accept(old).errors

    withdrawn = open_invitation("fay@example.com")
    gone = withdrawn.generate_token_for(:accept)
    withdrawn.destroy!
    assert_equal [ :expired ], accept(gone).errors

    assert_equal [ :expired ], accept("junk").errors
    assert_equal [ :expired ], accept(nil).errors
    assert_nil accept("junk").record

    assert @invitation.reload.open?
    assert_equal 0, User.where(email_address: %w[dana@example.com eli@example.com fay@example.com]).count
    assert_empty Audit::Event.all
  end

  test "a password that is blank, short or unconfirmed is refused, no account is made and the invitation stays open" do
    results = nil
    assert_no_difference [ -> { User.count }, -> { AccessControl::Membership.count } ] do
      results = [
        accept(password: "", password_confirmation: ""), accept(password: "short"),
        accept(password: "a-long-password-1", password_confirmation: "another-password"),
        accept(password: "a-long-password-1", password_confirmation: ""), accept(name: "x" * 121)
      ]
    end
    assert_includes results[0].errors, "Password can't be blank"
    assert_includes results[1].errors, "Use at least 12 characters."
    assert_includes results[2].errors, "Password confirmation doesn't match Password"
    assert_includes results[3].errors, "Password confirmation can't be blank"
    assert_includes results[4].errors, "Name is too long (maximum is 120 characters)"
    results.each do |result|
      assert_not result.ok?
      assert_equal @invitation, result.record
    end

    assert @invitation.reload.open?
    assert_empty Audit::Event.all
  end

  # The New user form made the account meanwhile: the person signs in.
  test "an address that has an account by now is used, and no second account is made" do
    User.create!(email_address: "dana@example.com", password: "a-long-password-1")

    assert_no_difference -> { User.count } do
      assert_equal [ :used ], accept.errors
    end
    assert @invitation.reload.open?
  end

  # A signed-in session in the same browser is not who accepts: the token is.
  test "whoever is signed in, the acceptance is the new account's" do
    result = as(users(:one)) { Invitations::Accept.call(token: @token, name: "", password: "a-long-password-1", password_confirmation: "a-long-password-1") }

    assert result.ok?
    assert_nil result.record.name
    assert_equal result.record.id, Audit::Event.find_by!(action: "invitation.accepted").user_id
  end
end
