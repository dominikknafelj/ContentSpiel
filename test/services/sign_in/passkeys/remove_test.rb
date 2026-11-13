require "test_helper"

class SignIn::Passkeys::RemoveTest < ActiveSupport::TestCase
  setup do
    @user = users(:reader)
    @first = add_passkey(@user, client: fake_authenticator, name: "MacBook")
    @codes = as(@user) { RecoveryCodes::Generate.call(@user) }.record
  end

  def remove(passkey, actor: @user)
    as(actor) { SignIn::Passkeys::Remove.call(passkey) }
  end

  def covered! = Current.site.update!(passkey_policy: "everyone")

  test "a passkey that is not the last goes alone, and the codes stay" do
    covered!
    second = add_passkey(@user, client: fake_authenticator, name: "Phone")

    result = remove(second)

    assert result.ok?, result.errors.inspect
    assert_equal [ @first ], @user.passkeys.reload.to_a
    assert_equal RecoveryCode::COUNT, @user.recovery_codes.unused.count
    event = Audit::Event.find_by!(action: "passkey.removed")
    assert_equal [ "Passkey", second.id, @user ], [ event.subject_type, event.subject_id, event.actor ]
    assert_equal "Phone", event.subject_label
    assert_equal({ "name" => "Phone", "recovery_codes_removed" => 0 }, event.metadata)
  end

  test "the last passkey of a covered person is refused, the passkey and codes stay, nothing is recorded" do
    covered!
    audit_before = Audit::Event.count

    result = remove(@first)

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "This site asks you to sign in with a passkey. Add another before removing this one." ], result.errors
    assert Passkey.exists?(@first.id)
    assert_equal RecoveryCode::COUNT, @user.recovery_codes.unused.count
    assert_equal audit_before, Audit::Event.count
  end

  test "the last passkey of an uncovered person goes with the codes, in one event" do
    Current.site.update!(passkey_policy: "owners_and_admins")
    audit_ids = Audit::Event.pluck(:id)

    result = remove(@first)

    assert result.ok?, result.errors.inspect
    assert_empty @user.passkeys.reload
    assert_empty @user.recovery_codes.reload
    assert_not @user.reload.second_factor?
    events = Audit::Event.where.not(id: audit_ids)
    assert_equal [ "passkey.removed" ], events.pluck(:action)
    assert_equal({ "name" => "MacBook", "recovery_codes_removed" => RecoveryCode::COUNT }, events.sole.metadata)
  end

  test "another user's passkey is denied and nothing is written" do
    result = remove(@first, actor: users(:one))

    assert result.denied?
    assert Passkey.exists?(@first.id)
    assert_equal RecoveryCode::COUNT, @user.recovery_codes.count
    assert_equal "access.denied", Audit::Event.order(:id).last.action
  end
end
