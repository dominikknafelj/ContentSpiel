require "test_helper"

# `Invitations::AcceptWithSso`: an open invitation accepted through the
# provider. The account is made linked, with a password nobody holds, in the
# invitation's groups, and both events are the new account's own.
class Invitations::AcceptWithSsoTest < ActiveSupport::TestCase
  ISSUER = "https://id.example.com/oauth2/default".freeze

  setup do
    @invitation = open_invitation("dana@example.com", name: "Dana", groups: [ access_control_groups(:read_only) ])
  end

  def identity(subject: "sub-dana", email: "dana@example.com", email_verified: true, name: "Dana Example")
    SignIn::Oidc::Identity.new(issuer: ISSUER, subject:, email:, email_verified:, name:, refresh_token: nil)
  end

  def accept(invitation = @invitation, identity: self.identity) = as(nil) { Invitations::AcceptWithSso.call(invitation, identity:) }

  test "makes the linked account in the invitation's groups, marks it accepted, and records invitation.accepted and sso.linked as the new user" do
    result = nil
    with_leaked_password_check(leaked: []) do
      assert_difference -> { User.count }, 1 do
        result = accept
      end
      assert_empty leaked_password_requests
    end

    assert result.ok?, result.errors.inspect
    user = result.record
    assert_equal [ "dana@example.com", "Dana Example", ISSUER, "sub-dana" ], user.values_at(:email_address, :name, :sso_issuer, :sso_subject)
    assert user.sso_linked_at.present?
    assert_not user.owner?
    assert_equal [ access_control_groups(:read_only) ], user.groups.to_a
    assert_equal user, @invitation.reload.user
    assert @invitation.accepted?

    accepted = Audit::Event.find_by!(action: "invitation.accepted")
    assert_equal [ user, user.id ], [ accepted.subject, accepted.user_id ]
    assert_equal({ "invitation_id" => @invitation.id }, accepted.metadata)
    linked = Audit::Event.find_by!(action: "sso.linked")
    assert_equal [ user, user.id ], [ linked.subject, linked.user_id ]
    assert_equal({ "via" => "invitation", "issuer_host" => "id.example.com", "passkeys_removed" => 0, "recovery_codes_removed" => 0 }, linked.metadata)
    assert_not_includes Audit::Event.all.to_json, "password_digest"
  end

  test "the provider's name is cut to a user's limit, and none is no name" do
    long = accept(identity: identity(name: "n" * 300))
    assert_equal 120, long.record.name.length

    other = open_invitation("eli@example.com")
    assert_nil accept(other, identity: identity(subject: "sub-eli", email: "eli@example.com", name: nil)).record.name
  end

  test "a second acceptance is used, and writes nothing" do
    assert accept.ok?
    events = Audit::Event.count

    second = accept(@invitation.reload, identity: identity(subject: "sub-other"))

    assert_equal [ :used ], second.errors
    assert_equal @invitation, second.record
    assert_equal events, Audit::Event.count
    assert_equal 1, User.where(email_address: "dana@example.com").count
  end

  test "an invitation whose address has an account is used, and a lapsed or withdrawn one expired" do
    as(nil) { User.create!(email_address: "dana@example.com", password: "a-long-password-1") }
    assert_equal [ :used ], accept.errors

    lapsed = open_invitation("eli@example.com", sent_at: (Invitation::VALID_FOR + 1.minute).ago)
    assert_equal [ :expired ], accept(lapsed, identity: identity(email: "eli@example.com")).errors

    withdrawn = open_invitation("fay@example.com")
    Invitation.where(id: withdrawn.id).delete_all
    assert_equal [ :expired ], accept(withdrawn, identity: identity(email: "fay@example.com")).errors
  end

  test "an identity whose email is not the invitation's verified one accepts nothing" do
    assert_equal [ :mismatch ], accept(identity: identity(email: "reader@example.com")).errors
    assert_equal [ :mismatch ], accept(identity: identity(email_verified: false)).errors
    assert @invitation.reload.open?
    assert_empty Audit::Event.all
  end

  test "a subject linked to another account makes no second account" do
    users(:reader).update_columns(sso_issuer: ISSUER, sso_subject: "sub-dana", sso_linked_at: 1.day.ago) # version: none (a test's setup)

    result = accept

    assert_equal [ :used ], result.errors
    assert_not User.exists?(email_address: "dana@example.com")
    assert @invitation.reload.open?
    assert_empty Audit::Event.all
  end
end
