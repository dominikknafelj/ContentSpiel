require "test_helper"

class Users::SaveTest < ActiveSupport::TestCase
  test "a blank password leaves the password alone" do
    user = users(:one)
    result = Users::Save.call(user, attributes: { email_address: "new@example.com", password: "", password_confirmation: "" }, actor: nil)

    assert result.ok?, result.errors.to_sentence
    assert user.reload.authenticate("password")
  end

  test "a password with a matching confirmation is changed" do
    user = users(:one)
    result = Users::Save.call(user, attributes: { password: "new-password-1", password_confirmation: "new-password-1" }, actor: nil)

    assert result.ok?, result.errors.to_sentence
    assert user.reload.authenticate("new-password-1")
  end

  # Final fix wave (C, P17): `has_secure_password` only compares the
  # confirmation when it's non-nil, and a form that omits it (or a caller
  # that forgets it) would otherwise set the password unconfirmed.
  test "a password without a confirmation is refused" do
    user = users(:one)
    [ { password: "new-password-1" }, { password: "new-password-1", password_confirmation: "" } ].each do |attributes|
      result = Users::Save.call(user, attributes: attributes, actor: nil)

      assert_not result.ok?
      assert_includes result.errors, "Password confirmation can't be blank"
      assert user.reload.authenticate("password")
    end
  end

  test "a new user needs a confirmation too" do
    result = Users::Save.call(attributes: { email_address: "fresh@example.com", password: "new-password-1" }, actor: nil)

    assert_not result.ok?
    assert_not User.exists?(email_address: "fresh@example.com")
  end
end
