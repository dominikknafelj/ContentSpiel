require "test_helper"

class RecoveryCodeTest < ActiveSupport::TestCase
  def add_code(user, text) = user.recovery_codes.create!(digest: RecoveryCode.digest(text), generated_at: Time.current)

  test "a code is found however it is typed: lower case, spaces, a missing hyphen, O for 0 and I or L for 1" do
    digest = RecoveryCode.digest("ABCD-EFGH")

    assert_not_nil digest
    assert_equal digest, RecoveryCode.digest("abcd efgh")
    assert_equal digest, RecoveryCode.digest("ABCDEFGH")
    assert_equal digest, RecoveryCode.digest(" abcd-efgh ")
    assert_equal RecoveryCode.digest("0011-AB01"), RecoveryCode.digest("OoIl-abOi")
    assert_nil RecoveryCode.digest("0O1I"), "too short"
    assert_nil RecoveryCode.digest("ABCD-EFGHJ"), "too long"
    assert_nil RecoveryCode.digest("ABCD-EFGU"), "U is not in the alphabet"
    assert_nil RecoveryCode.digest("ABCD-EF*H")
    assert_nil RecoveryCode.digest([ "x" ])
    assert_nil RecoveryCode.digest(nil)
  end

  test "texts are ten distinct codes of the alphabet in XXXX-XXXX" do
    texts = RecoveryCode.texts
    shape = /\A[#{RecoveryCode::ALPHABET}]{4}-[#{RecoveryCode::ALPHABET}]{4}\z/

    assert_equal RecoveryCode::COUNT, texts.size
    assert_equal texts.size, texts.uniq.size
    texts.each { |text| assert_match shape, text }
    assert_not_equal texts, RecoveryCode.texts
  end

  test "a code is redeemed once; the second redeem of it and a redeem of an unknown code are false" do
    user = users(:reader)
    add_code(user, "ABCD-EFGH")
    other = add_code(users(:two), "JKMN-PQRS")
    at = Time.zone.local(2026, 11, 12, 9, 0, 0)

    assert users(:reader).recovery_codes.redeem("abcd efgh", at: at)
    assert_equal at, user.recovery_codes.sole.used_at
    assert_not users(:reader).recovery_codes.redeem("ABCD-EFGH")
    assert_not users(:reader).recovery_codes.redeem("ZZZZ-ZZZZ")
    assert_not users(:reader).recovery_codes.redeem("JKMN-PQRS"), "another account's code"
    assert_nil other.reload.used_at
    assert_not users(:reader).recovery_codes.redeem(nil)
  end

  test "the digest is an HMAC under the application's key, never the code itself" do
    digest = RecoveryCode.digest("ABCD-EFGH")

    assert_match(/\A\h{64}\z/, digest)
    assert_not_includes digest, "ABCDEFGH"
  end
end
