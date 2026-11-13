require "test_helper"

# `Sso::Link`: an account linked to a provider's subject
# signs in through the provider alone, so its password becomes one nobody
# holds, its sessions end, and its passkeys and recovery codes go.
class Sso::LinkTest < ActiveSupport::TestCase
  ISSUER = "https://id.example.com/oauth2/default".freeze

  setup { @user = users(:reader) }

  def identity(subject: "sub-1", email: "reader@example.com")
    SignIn::Oidc::Identity.new(issuer: ISSUER, subject:, email:, email_verified: true, name: nil, refresh_token: nil)
  end

  def link(user = @user, identity: self.identity, via: "sign_in") = as(nil) { Sso::Link.call(user, identity:, via:) }

  test "linking stores the subject, makes the password unusable, ends every session, deletes passkeys and codes and records sso.linked" do
    2.times { Session.start(user: @user, method: "password", user_agent: nil, ip_address: nil) }
    add_passkey(@user, client: fake_authenticator)
    3.times { |index| @user.recovery_codes.create!(digest: RecoveryCode.digest("AAAA#{index}BCD"), generated_at: Time.current) }

    result = nil
    with_leaked_password_check(leaked: []) do
      result = link
      assert_empty leaked_password_requests, "a password nobody typed is not looked up"
    end

    assert result.ok?, result.errors.inspect
    @user.reload
    assert_equal [ ISSUER, "sub-1" ], [ @user.sso_issuer, @user.sso_subject ]
    assert_in_delta Time.current, @user.sso_linked_at, 5
    assert_not @user.authenticate("password")
    assert_empty @user.sessions
    assert_empty @user.passkeys
    assert_empty @user.recovery_codes

    linked = Audit::Event.find_by!(action: "sso.linked")
    assert_equal [ @user, @user, @user.id ], [ linked.actor, linked.subject, linked.user_id ]
    assert_equal({ "via" => "sign_in", "issuer_host" => "id.example.com", "passkeys_removed" => 1, "recovery_codes_removed" => 3 }, linked.metadata)
    updated = Audit::Event.find_by!(action: "user.updated")
    assert_equal @user, updated.actor
    assert_equal [ nil, "password changed" ], updated.field_changes["credentials"]
    assert_equal [ nil, "sub-1" ], updated.field_changes["sso_subject"]
    ended = Audit::Event.find_by!(action: "session.ended")
    assert_equal({ "reason" => "password_changed", "count" => 2 }, ended.metadata)
    assert_not_includes Audit::Event.all.to_json, "password_digest"
  end

  test "a reset link issued before linking no longer works" do
    token = @user.password_reset_token
    assert_equal @user, User.find_by_password_reset_token(token)

    assert link.ok?

    assert_nil User.find_by_password_reset_token(token)
  end

  test "an owner is never linked" do
    result = link(users(:one), identity: identity(email: "one@example.com"))

    assert_equal [ :owner ], result.errors
    assert_not users(:one).reload.sso_linked?
    assert users(:one).authenticate("password")
    assert_empty Audit::Event.where(action: %w[sso.linked user.updated])
  end

  test "an account is linked once: the same subject again changes nothing, another is refused" do
    assert link.ok?
    linked_at = @user.reload.sso_linked_at

    again = link(User.find(@user.id))
    assert again.ok?, again.errors.inspect
    assert_equal linked_at, @user.reload.sso_linked_at
    assert_equal 1, Audit::Event.where(action: "sso.linked").count

    other = link(User.find(@user.id), identity: identity(subject: "sub-2"))
    assert_equal [ :linked ], other.errors
    assert_equal "sub-1", @user.reload.sso_subject
  end

  test "a subject linked to another account is never linked to a second, and nothing is written" do
    users(:two).update_columns(sso_issuer: ISSUER, sso_subject: "sub-1", sso_linked_at: 1.day.ago) # version: none (a test's setup)
    Session.start(user: @user, method: "password", user_agent: nil, ip_address: nil)

    result = link

    assert_equal [ :raced ], result.errors
    assert_not @user.reload.sso_linked?
    assert @user.authenticate("password")
    assert_equal 1, @user.sessions.count
    assert_empty Audit::Event.where(action: %w[sso.linked user.updated session.ended])
  end

  test "a password that cannot be cleared raises, rolls back whole, and leaves the caller's account unlinked in memory" do
    with_singleton_override(Users::UpdatePassword, :call, ->(*, **) { ApplicationService::Result.failure(nil, [ "Password could not be saved" ]) }) do
      assert_raises(Sso::Link::NotCleared) { link }
    end

    assert_not @user.sso_linked?, "the object the caller holds was read again"
    assert_nil @user.sso_issuer
    assert_not @user.reload.sso_linked?
    assert_empty Audit::Event.where(action: "sso.linked")
  end

  test "an unknown via is a mistake of the caller's" do
    assert_raises(ArgumentError) { link(via: "console") }
  end
end
