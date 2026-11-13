require "test_helper"

class SignInMethodsTest < ActiveSupport::TestCase
  setup { SignInMethods.reset! }
  teardown { Rails.application.reloader.prepare! }

  def register(name = "acme/saml", **options)
    SignInMethods.register(name, label: "acme.sign_in.saml", path: :admin_root_path, **options)
  end

  test "register keeps entries in order, found by name, with the defaults" do
    first = register("acme/saml")
    register("acme/ldap")
    assert_equal %w[acme/saml acme/ldap], SignInMethods.names
    assert_equal first, SignInMethods.find("acme/saml")
    assert_equal first, SignInMethods.find(:"acme/saml")
    assert_nil first.recheck
    assert_equal :applies, first.passkey_policy
    assert_nil SignInMethods.find("acme/none")
  end

  test "a duplicate name, an unknown passkey policy and a recheck that is not callable are refused" do
    register
    assert_raises(ArgumentError) { register }
    assert_includes assert_raises(ArgumentError) { register("acme/x", passkey_policy: :maybe) }.message, "applies, exempt"
    assert_raises(ArgumentError) { register("acme/y", recheck: Object.new) }
  end

  test "exempt? is true for sso and an exempt entry, false for password and an applying entry" do
    register("acme/exempt", passkey_policy: :exempt)
    register("acme/applies")
    assert SignInMethods.exempt?("sso")
    assert SignInMethods.exempt?("acme/exempt")
    assert_not SignInMethods.exempt?("password")
    assert_not SignInMethods.exempt?("passkey")
    assert_not SignInMethods.exempt?("acme/applies")
    assert_not SignInMethods.exempt?("acme/unknown")
  end

  # `Sso::RecheckJob` calls `recheck.call(session)`; the entry's shape is its contract.
  test "a recheck is called as call(session) and answers ok, revoked or unavailable" do
    recheck = ->(session) { session.is_a?(Session) ? :ok : :unavailable }
    entry = register(recheck: recheck)
    assert_equal :ok, entry.recheck.call(Session.new)
    assert_raises(ArgumentError) { entry.recheck.call }
  end

  test "reset! empties the registry" do
    register
    SignInMethods.reset!
    assert_empty SignInMethods.entries
  end
end
