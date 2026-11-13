require "test_helper"

# Who may sign in with a password or a passkey, and whose reset request is
# answered with the reminder to use the provider.
class SignInRulesTest < ActiveSupport::TestCase
  test "without single sign-on everyone may use a password and a passkey, and nobody gets the reminder" do
    [ users(:one), users(:reader) ].each do |user|
      assert SignInRules.password_allowed?(user)
      assert SignInRules.passkey_allowed?(user)
      assert_not SignInRules.reminder_instead_of_reset?(user)
    end
  end

  test "with single sign-on not required only a linked account is refused, and gets the reminder" do
    with_sso do
      assert SignInRules.password_allowed?(users(:reader))
      assert SignInRules.password_allowed?(users(:one))

      link_to_sso(users(:reader))
      assert_not SignInRules.password_allowed?(users(:reader))
      assert_not SignInRules.passkey_allowed?(users(:reader))
      assert SignInRules.reminder_instead_of_reset?(users(:reader))
    end
  end

  test "under SSO_REQUIRED every non-owner is refused and gets the reminder, and an owner keeps the password and the passkey" do
    with_sso(required: true) do
      assert_not SignInRules.password_allowed?(users(:reader))
      assert_not SignInRules.passkey_allowed?(users(:two))
      assert SignInRules.reminder_instead_of_reset?(users(:reader))

      assert SignInRules.password_allowed?(users(:one))
      assert SignInRules.passkey_allowed?(users(:one))
      assert_not SignInRules.reminder_instead_of_reset?(users(:one))
    end
  end

  test "a linked account stays refused with single sign-on off: the link, not the provider, decides" do
    link_to_sso(users(:reader))

    assert_not SignInRules.password_allowed?(users(:reader))
    assert_not SignInRules.passkey_allowed?(users(:reader))
    assert SignInRules.reminder_instead_of_reset?(users(:reader))
  end

  test "the provider's name is the configured one, else the host the account was linked under" do
    link_to_sso(users(:reader))
    assert_equal "id.example.com", SignInRules.provider_name(users(:reader))
    with_sso { assert_equal OidcHelper::NAME, SignInRules.provider_name(users(:reader)) }
  end
end
