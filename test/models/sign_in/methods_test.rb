require "test_helper"

class SignIn::MethodsTest < ActiveSupport::TestCase
  setup { SignIn::Methods.reset! }
  teardown { Rails.application.reloader.prepare! }

  def register(name = "acme/saml", **options)
    SignIn::Methods.register(name, label: "acme.sign_in.saml", path: :admin_root_path, **options)
  end

  test "register keeps entries in order, found by name, with the defaults" do
    first = register("acme/saml")
    register("acme/ldap")
    assert_equal %w[acme/saml acme/ldap], SignIn::Methods.names
    assert_equal first, SignIn::Methods.find("acme/saml")
    assert_equal first, SignIn::Methods.find(:"acme/saml")
    assert_nil first.recheck
    assert_equal :applies, first.passkey_policy
    assert_nil SignIn::Methods.find("acme/none")
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
    assert SignIn::Methods.exempt?("sso")
    assert SignIn::Methods.exempt?("acme/exempt")
    assert_not SignIn::Methods.exempt?("password")
    assert_not SignIn::Methods.exempt?("passkey")
    assert_not SignIn::Methods.exempt?("acme/applies")
    assert_not SignIn::Methods.exempt?("acme/unknown")
  end

  # `SignIn::Sso::RecheckJob` calls `recheck.call(session)`; the entry's shape is its contract.
  test "a recheck is called as call(session) and answers ok, revoked or unavailable" do
    recheck = ->(session) { session.is_a?(Session) ? :ok : :unavailable }
    entry = register(recheck: recheck)
    assert_equal :ok, entry.recheck.call(Session.new)
    assert_raises(ArgumentError) { entry.recheck.call }
  end

  test "reset! empties the registry" do
    register
    SignIn::Methods.reset!
    assert_empty SignIn::Methods.entries
  end
end
