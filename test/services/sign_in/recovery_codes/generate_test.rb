require "test_helper"

class SignIn::RecoveryCodes::GenerateTest < ActiveSupport::TestCase
  setup do
    @user = users(:reader)
    add_passkey(@user, client: fake_authenticator)
  end

  def generate(actor: @user) = as(actor) { SignIn::RecoveryCodes::Generate.call(@user) }

  test "regenerating replaces every code, used ones too, and records how many unused it replaced" do
    first = generate.record
    first.first(3).each { |code| assert @user.recovery_codes.redeem(code) }

    result = generate

    assert result.ok?, result.errors.inspect
    assert_equal RecoveryCode::COUNT, result.record.size
    assert_empty first & result.record
    assert_equal RecoveryCode::COUNT, @user.recovery_codes.count
    assert_equal RecoveryCode::COUNT, @user.recovery_codes.unused.count
    assert_equal 1, @user.recovery_codes.distinct.count(:generated_at)

    events = Audit::Event.where(action: "recovery_codes.generated").order(:id)
    assert_equal [ { "count" => 10, "replaced" => 0 }, { "count" => 10, "replaced" => 7 } ], events.map(&:metadata)
    assert_equal [ @user ], events.map(&:subject).uniq
    assert_equal [ @user ], events.map(&:actor).uniq
    assert_not_includes events.map(&:attributes).to_json, first.first.delete("-")
  end

  test "a code from before regenerating no longer redeems" do
    old = generate.record
    fresh = generate.record

    assert_not @user.recovery_codes.redeem(old.first)
    assert @user.recovery_codes.redeem(fresh.first)
  end

  test "another user's codes are denied and nothing is written" do
    result = generate(actor: users(:one))

    assert result.denied?
    assert_empty @user.recovery_codes
    assert_equal [ "access.denied" ], Audit::Event.pluck(:action)
  end

  # Codes are a backup for passkeys: alone they would be the account's only
  # second factor, asked at every sign-in until the ten were spent.
  test "a person with no passkey is refused, and nothing is written or recorded" do
    @user.passkeys.delete_all

    result = generate

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ SignIn::RecoveryCodes::Generate.passkey_first ], result.errors
    assert_empty @user.recovery_codes
    assert_empty Audit::Event.where(action: "recovery_codes.generated")
  end

  test "a linked account makes no recovery codes" do
    link_to_sso(@user)

    result = generate

    assert result.denied?
    assert_empty @user.recovery_codes
    assert_not Audit::Event.exists?(action: "recovery_codes.generated")
  end
end
