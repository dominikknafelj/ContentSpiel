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
    assert_includes result.record.errors[:current_password], "That's not your current password."
    assert_equal [ "That's not your current password." ], result.errors
    assert users(:reader).reload.authenticate("password")

    result = as(users(:reader)) { change(users(:reader), actor: users(:reader), current_password: "password") }
    assert result.ok?, result.errors.inspect
  end

  test "a blank or unconfirmed password fails" do
    blank = as(users(:reader)) { Users::UpdatePassword.call(users(:reader), password: "", password_confirmation: "", actor: users(:reader)) }
    assert_includes blank.record.errors[:password], "Password can't be blank"

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

  # Fix round 1 (I1): a non-owner can't reset the password of someone whose
  # rights exceed theirs.
  test "a user manager can't reset a more privileged user's password" do
    managers = AccessControl::Group.create!(name: "User managers")
    AccessControl::Grant.create!(group: managers, permission: "users.manage", scope: {})
    AccessControl::Grant.create!(group: managers, permission: "posts.read", scope: {})
    AccessControl::Grant.create!(group: managers, permission: "pages.read", scope: {})
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)

    as(users(:editor_branch)) do
      refused = Users::UpdatePassword.call(users(:two), password: "taken-over-1", password_confirmation: "taken-over-1")
      assert refused.denied?
      assert_equal [ "You don't have permission to manage users" ], refused.errors

      assert Users::UpdatePassword.call(users(:reader), password: "reset-pass-1", password_confirmation: "reset-pass-1").ok?
    end
    assert users(:two).reload.authenticate("password")
    assert users(:reader).reload.authenticate("reset-pass-1")
  end

  # --- clear: a password nobody holds (Sso::Link) -----------------------------

  test "clear needs the user's own actor or the console, and never asks the leak lookup" do
    clear = ->(user, actor:) { Users::UpdatePassword.call(user, clear: true, keep_acting_session: false, actor: actor) }
    sessions = 2.times.map { Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil) }

    with_leaked_password_check(leaked: []) do
      [ users(:two), users(:one), users(:author) ].each do |someone|
        refused = as(someone) { clear.call(users(:reader), actor: someone) }
        assert refused.denied?, "#{someone.email_address} may not clear another person's password"
      end
      assert users(:reader).reload.authenticate("password")
      sessions.each { |session| assert Session.exists?(session.id) }

      own = as(nil) { clear.call(users(:reader), actor: users(:reader)) }
      assert own.ok?, own.errors.inspect
      assert_not users(:reader).reload.authenticate("password")
      sessions.each { |session| assert_not Session.exists?(session.id) }
      assert_equal [ nil, "password changed" ], Audit::Event.find_by!(action: "user.updated").field_changes["credentials"]
      assert_equal "password_changed", Audit::Event.find_by!(action: "session.ended").metadata["reason"]

      console = as(nil, channel: :console) { clear.call(users(:author), actor: nil) }
      assert console.ok?, console.errors.inspect
      assert_not users(:author).reload.authenticate("password")

      assert_empty leaked_password_requests
    end
  end

  test "clear does not open sign-in: nobody can type the password it writes" do
    throttle = SignIn::Protection::Throttle.new
    cleared = []
    with_singleton_override(SignIn::Protection::Throttle, :new, ->(**) { throttle }) do
      with_singleton_override(throttle, :clear, ->(identifier:) { cleared << identifier }) do
        as(nil) { Users::UpdatePassword.call(users(:reader), clear: true, keep_acting_session: false, actor: users(:reader)) }
        assert_empty cleared
        as(nil) { change(users(:reader), actor: users(:reader)) }
        assert_equal [ "reader@example.com" ], cleared
      end
    end
  end

  # --- Leaked passwords (Users::LeakedPasswordRule) ---------------------------

  test "a leaked password is refused and the user's sessions all stay" do
    leaked = "correct horse battery"
    sessions = 2.times.map { Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil) }

    with_leaked_password_check(leaked: [ leaked ]) do
      result = nil
      assert_no_difference -> { Audit::Event.count } do
        result = as(nil) { Users::UpdatePassword.call(users(:reader), password: leaked, password_confirmation: leaked, keep_acting_session: false, actor: users(:reader)) }
      end

      assert_not result.ok?
      assert_equal [ "This password is in a list of leaked passwords, so it isn't safe to use. Choose another one." ], result.errors
      assert_equal result.errors, result.record.errors[:password]
      assert_equal 1, leaked_password_requests.size
    end
    assert users(:reader).reload.authenticate("password")
    sessions.each { |session| assert Session.exists?(session.id) }
  end

  test "a password the model refuses is never looked up, and a wrong current password neither" do
    with_leaked_password_check(leaked: [ "correct horse battery" ]) do
      as(users(:reader)) do
        Users::UpdatePassword.call(users(:reader), password: "short", password_confirmation: "short", actor: users(:reader))
        Users::UpdatePassword.call(users(:reader), password: "correct horse battery", password_confirmation: "other", actor: users(:reader))
        Users::UpdatePassword.call(users(:reader), password: "correct horse battery", password_confirmation: "correct horse battery", current_password: "wrong", actor: users(:reader))
      end
      assert_empty leaked_password_requests
    end
  end

  # --- A password change ends that user's sessions ---------------------------

  test "an admin changing someone's password ends every session of that user, the admin's own untouched" do
    target = Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil)
    mine = Session.start(user: users(:two), method: "password", user_agent: nil, ip_address: nil)

    result = Current.set(session: mine) { as(users(:two)) { change(users(:reader), actor: users(:two)) } }

    assert result.ok?, result.errors.inspect
    assert_not Session.exists?(target.id)
    assert Session.exists?(mine.id)
  end

  test "changing your own password keeps the session you act in and ends the others" do
    current = Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil)
    other = Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil)

    result = Current.set(session: current) { as(users(:reader)) { change(users(:reader), actor: users(:reader)) } }

    assert result.ok?, result.errors.inspect
    assert Session.exists?(current.id)
    assert_not Session.exists?(other.id)
  end

  # The reset flow: the emailed token is what authenticated the change, no
  # session is acting, so there is none to keep.
  test "the reset flow ends every session of the user" do
    2.times { Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil) }

    result = as(nil) { change(users(:reader), actor: users(:reader), keep_acting_session: false) }

    assert result.ok?, result.errors.inspect
    assert_empty users(:reader).sessions.reload
  end

  test "a change that ends sessions records one session.ended with the count, the user its subject" do
    2.times { Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil) }

    as(users(:two)) { change(users(:reader), actor: users(:two)) }

    event = Audit::Event.where(action: "session.ended").sole
    assert_equal({ "reason" => "password_changed", "count" => 2 }, event.metadata)
    assert_equal users(:reader), event.subject
    assert_equal users(:two), event.actor
  end

  test "a change of your own password with no other session open records no session.ended" do
    current = Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil)

    result = Current.set(session: current) { as(users(:reader)) { change(users(:reader), actor: users(:reader)) } }

    assert result.ok?, result.errors.inspect
    assert Session.exists?(current.id)
    assert_not Audit::Event.exists?(action: "session.ended")
  end

  test "the reset flow's ending is recorded as the user's" do
    Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil)

    as(nil) { change(users(:reader), actor: users(:reader), keep_acting_session: false) }

    event = Audit::Event.where(action: "session.ended").sole
    assert_equal({ "reason" => "password_changed", "count" => 1 }, event.metadata)
    assert_equal users(:reader), event.actor
  end

  test "a failed change ends no session" do
    session = Session.start(user: users(:reader), method: "password", user_agent: nil, ip_address: nil)

    result = as(users(:reader)) { change(users(:reader), actor: users(:reader), current_password: "wrong") }

    assert_not result.ok?
    assert Session.exists?(session.id)
  end

  # --- The console clears a lost person's passkeys --------------------------

  def with_passkeys_and_codes(user)
    2.times { |index| add_passkey(user, client: fake_authenticator, name: "Key #{index}") }
    as(user) { RecoveryCodes::Generate.call(user) }
    2.times { Session.start(user: user, method: "passkey", user_agent: nil, ip_address: nil) }
    user
  end

  test "remove_passkeys from the console removes passkeys and codes, ends every session and records one passkey.removed" do
    owner = with_passkeys_and_codes(users(:one))
    audit_ids = Audit::Event.pluck(:id)

    result = as(nil, channel: :console) { change(owner, actor: nil, remove_passkeys: true) }

    assert result.ok?, result.errors.inspect
    assert owner.reload.authenticate("brand-new-pass")
    assert_empty owner.passkeys
    assert_empty owner.recovery_codes
    assert_empty owner.sessions
    assert_not owner.second_factor?

    events = Audit::Event.where.not(id: audit_ids)
    removed = events.where(action: "passkey.removed").sole
    assert_equal({ "count" => 2, "recovery_codes_removed" => RecoveryCode::COUNT, "reason" => "console" }, removed.metadata)
    assert_equal owner, removed.subject
    assert_nil removed.actor
    assert_equal "console", removed.channel
    assert_equal({ "reason" => "password_changed", "count" => 2 }, events.find_by!(action: "session.ended").metadata)
  end

  test "remove_passkeys from a signed-in actor is denied and changes nothing" do
    owner = with_passkeys_and_codes(users(:one))
    reader = with_passkeys_and_codes(users(:reader))

    [ [ owner, owner ], [ owner, reader ] ].each do |actor, user|
      audit_ids = Audit::Event.pluck(:id)

      result = as(actor) { change(user, actor: actor, remove_passkeys: true) }

      assert result.denied?, "#{actor.email_address} on #{user.email_address}"
      assert_equal [ "access.denied" ], Audit::Event.where.not(id: audit_ids).pluck(:action)
    end
    [ owner, reader ].each do |user|
      assert user.reload.authenticate("password")
      assert_equal 2, user.passkeys.count
      assert_equal RecoveryCode::COUNT, user.recovery_codes.count
      assert_equal 2, user.sessions.count
    end
  end

  test "the console's password change leaves passkeys alone unless asked" do
    owner = with_passkeys_and_codes(users(:one))

    assert as(nil, channel: :console) { change(owner, actor: nil) }.ok?

    assert_equal 2, owner.passkeys.count
    assert_not Audit::Event.exists?(action: "passkey.removed")
  end

  test "a password for a linked account is refused with the sentence, its own or a manager's; clearing it is not" do
    user = link_to_sso(users(:reader))
    digest = user.password_digest

    [ user, users(:one) ].each do |actor|
      target = actor == user ? user : User.find(user.id)
      result = as(actor) { change(target, actor: actor) }
      assert_not result.ok?, actor.email_address
      assert_equal [ "This account signs in with id.example.com and has no password here." ], result.errors
    end
    assert_equal digest, user.reload.password_digest
    assert_not Audit::Event.exists?(action: "user.updated")

    assert as(user) { Users::UpdatePassword.call(user, clear: true, keep_acting_session: false, actor: user) }.ok?
  end

  test "a refusal of a linked account asks the authorization first: a stranger learns no link" do
    user = link_to_sso(users(:reader))

    result = as(users(:author)) { change(user, actor: users(:author)) }

    assert result.denied?
  end

  test "a link that lands between the read and the change is seen under the row lock" do
    user = User.find(users(:reader).id)
    digest = user.password_digest
    link_to_sso(User.find(user.id))

    result = as(user) { change(user, actor: user) }

    assert_not result.ok?
    assert_equal [ "This account signs in with id.example.com and has no password here." ], result.errors
    assert_equal digest, users(:reader).reload.password_digest
    assert_not Audit::Event.exists?(action: "user.updated")
  end
end
