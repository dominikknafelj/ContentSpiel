require "test_helper"

class PasskeyTest < ActiveSupport::TestCase
  def build(name) = users(:reader).passkeys.new(name: name, external_id: SecureRandom.urlsafe_base64(32), public_key: "pk")

  test "a passkey's name is stripped, required and at most 60 characters, and the blank message is the dialog's sentence" do
    assert_equal "MacBook", build("  MacBook \n").tap(&:validate).name

    blank = build("   ")
    assert_not blank.valid?
    assert_equal [ "Give the passkey a name." ], blank.errors.full_messages

    assert build("a" * Passkey::NAME_LIMIT).valid?
    long = build("a" * (Passkey::NAME_LIMIT + 1))
    assert_not long.valid?
    assert long.errors.of_kind?(:name, :too_long)
  end

  test "used! writes the count and the time without moving updated_at, and the user handle is the user's" do
    passkey = build("Phone").tap(&:save!)
    stamp = passkey.updated_at
    at = Time.zone.local(2026, 11, 12, 9, 0, 0)

    passkey.used!(sign_count: 7, at: at)

    passkey.reload
    assert_equal 7, passkey.sign_count
    assert_equal at, passkey.last_used_at
    assert_equal stamp, passkey.updated_at
    assert_equal users(:reader).webauthn_handle!, passkey.user_handle
  end
end
