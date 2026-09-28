require "test_helper"

class Users::UpdatePasswordTest < ActiveSupport::TestCase
  def change(user, actor:, **options)
    Users::UpdatePassword.call(user, password: "brand-new-pass", password_confirmation: "brand-new-pass", actor: actor, **options)
  end

  test "anyone may change their own password, and the log never sees it" do
    result = as(users(:reader)) { change(users(:reader), actor: users(:reader)) }

    assert result.ok?, result.errors.inspect
    assert users(:reader).reload.authenticate("brand-new-pass")
    event = Audit::Event.find_by!(action: "user.updated")
    assert_equal users(:reader), event.actor
    assert_equal({ "credentials" => [ nil, "password changed" ] }, event.field_changes)
    assert_not_includes event.attributes.to_json, "brand-new-pass"
    assert_not_includes event.attributes.to_json, "password_digest"
  end

  # The reset flow: nobody is signed in (nil `Current.actor` on :admin),
  # the controller passes the user the reset token authenticated.
  test "the reset flow passes the user as the actor and is recorded as theirs" do
    result = as(nil) { change(users(:reader), actor: users(:reader)) }

    assert result.ok?, result.errors.inspect
    assert_equal users(:reader), Audit::Event.find_by!(action: "user.updated").actor
  end

  test "a given current password must match" do
    result = as(users(:reader)) { change(users(:reader), actor: users(:reader), current_password: "wrong") }

    assert_not result.ok?
    assert_includes result.record.errors[:current_password], "is incorrect"
    assert users(:reader).reload.authenticate("password")

    result = as(users(:reader)) { change(users(:reader), actor: users(:reader), current_password: "password") }
    assert result.ok?, result.errors.inspect
  end

  test "a blank or unconfirmed password fails" do
    blank = as(users(:reader)) { Users::UpdatePassword.call(users(:reader), password: "", password_confirmation: "", actor: users(:reader)) }
    assert_includes blank.record.errors[:password], "can't be blank"

    mismatched = as(users(:reader)) { Users::UpdatePassword.call(users(:reader), password: "one-password", password_confirmation: "another", actor: users(:reader)) }
    assert_not mismatched.ok?
    assert users(:reader).reload.authenticate("password")
  end

  test "someone else's password needs users.manage, and an owner's needs an owner" do
    denied = as(users(:author)) { change(users(:reader), actor: users(:author)) }
    assert_equal [ "You don't have permission to manage users" ], denied.errors

    assert as(users(:two)) { change(users(:reader), actor: users(:two)) }.ok?

    owner = as(users(:two)) { change(users(:one), actor: users(:two)) }
    assert_equal [ "You don't have permission to change an owner's account" ], owner.errors
    assert users(:one).reload.authenticate("password")
  end

  test "an API token can't change its own user's password without users.manage" do
    token = ApiToken.generate!(users(:reader), group: access_control_groups(:read_only)).first

    result = as(token, channel: :mcp) { change(users(:reader), actor: token) }
    assert_not result.ok?
  end
end
