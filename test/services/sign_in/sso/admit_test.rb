require "test_helper"

# `SignIn::Sso::Admit`: which account a provider's identity signs into, in
# one order -- the link, then a verified email (an invitation's first, when
# the start came from one), then an open invitation -- and nothing else.
class SignIn::Sso::AdmitTest < ActiveSupport::TestCase
  include LogCapture
  ISSUER = "https://id.example.com/oauth2/default".freeze

  def identity(subject: "sub-1", email: "reader@example.com", email_verified: true, name: "Rea Der", issuer: ISSUER)
    SignIn::Sso::Identity.new(issuer:, subject:, email:, email_verified:, name:, refresh_token: nil)
  end

  def admit(identity, invitation: nil) = as(nil) { SignIn::Sso::Admit.call(identity, invitation:) }

  def refusals = Audit::Event.where(action: "sso.refused")

  test "a linked subject is its account, whatever email the provider now gives" do
    users(:reader).update_columns(sso_issuer: ISSUER, sso_subject: "sub-1", sso_linked_at: 1.day.ago) # version: none (a test's setup)

    result = admit(identity(email: "someone-else@example.com", email_verified: false))

    assert result.ok?, result.errors.inspect
    assert_equal users(:reader), result.record
    assert_empty refusals
    assert_empty Audit::Event.where(action: "sso.linked"), "an account already linked is not linked again"
  end

  test "a second subject with a linked account's email is refused and the link is unchanged; the linked subject with a new email still signs in" do
    first = admit(identity(subject: "sub-1"))
    assert first.ok?, first.errors.inspect
    assert_equal users(:reader), first.record

    second = admit(identity(subject: "sub-2"))

    assert_not second.ok?
    assert_nil second.record
    assert_equal [ "no_account" ], second.errors
    assert_equal [ ISSUER, "sub-1" ], users(:reader).reload.values_at(:sso_issuer, :sso_subject)
    assert_equal({ "reason" => "no_account", "issuer_host" => "id.example.com", "email" => "reader@example.com" }, refusals.sole.metadata)

    moved = admit(identity(subject: "sub-1", email: "reader-new@example.com"))
    assert moved.ok?, moved.errors.inspect
    assert_equal users(:reader), moved.record
  end

  test "a subject of another issuer is not the link, and the linked email then refuses it" do
    users(:reader).update_columns(sso_issuer: "https://other.example.com", sso_subject: "sub-1", sso_linked_at: 1.day.ago) # version: none (a test's setup)

    result = admit(identity(subject: "sub-1"))

    assert_equal [ "no_account" ], result.errors
    assert_equal "https://other.example.com", users(:reader).reload.sso_issuer
  end

  test "an unverified email links nothing and records sso.refused email_unverified" do
    result = admit(identity(email_verified: false))

    assert_equal [ "email_unverified" ], result.errors
    assert_not users(:reader).reload.sso_linked?
    assert users(:reader).authenticate("password")
    event = refusals.sole
    assert_equal({ "reason" => "email_unverified", "issuer_host" => "id.example.com", "email" => "reader@example.com" }, event.metadata)
    assert_nil event.actor_id
    assert_nil event.user_id
    assert_nil event.subject_type
  end

  test "an unverified email is refused even when the start came from that email's invitation" do
    invitation = open_invitation("dana@example.com")

    result = admit(identity(email: "dana@example.com", email_verified: false), invitation: invitation)

    assert_equal [ "email_unverified" ], result.errors
    assert invitation.reload.open?
  end

  test "an owner's email is refused and the owner keeps their password" do
    result = admit(identity(email: " ONE@example.com "))

    assert_equal [ "owner" ], result.errors
    owner = users(:one).reload
    assert_not owner.sso_linked?
    assert owner.authenticate("password")
    assert_equal "owner", refusals.sole.metadata["reason"]
  end

  test "SignIn::Sso::Admit.refuse, the callback's owner defence, writes the same refusal as #call, as nobody, whoever is signed in" do
    result = as(users(:two)) { SignIn::Sso::Admit.refuse(identity(email: "One@Example.com"), SignIn::Sso::Admit::OWNER) }

    assert_equal [ "owner" ], result.errors
    refusal = refusals.sole
    assert_nil refusal.actor_id
    assert_nil refusal.subject_id
    assert_equal({ "reason" => "owner", "issuer_host" => "id.example.com", "email" => "one@example.com" }, refusal.metadata)
  end

  test "an owner is never signed in by a link, however it came to be" do
    users(:one).update_columns(sso_issuer: ISSUER, sso_subject: "sub-1", sso_linked_at: 1.day.ago) # version: none (a test's setup)

    result = admit(identity(email: "one@example.com"))

    assert_equal [ "owner" ], result.errors
    assert_nil result.record
  end

  test "an email with no account and no invitation is refused as no_account, with the email in the event and nowhere else" do
    log = capture_log do
      result = admit(identity(email: "Stranger@Example.com"))
      assert_equal [ "no_account" ], result.errors
    end

    event = refusals.sole
    assert_equal({ "reason" => "no_account", "issuer_host" => "id.example.com", "email" => "stranger@example.com" }, event.metadata)
    assert_nil event.snapshot
    assert_equal({}, event.field_changes)
    assert_not_includes log.downcase, "stranger@example.com"
    assert_equal 1, Audit::Event.where("metadata::text ILIKE ?", "%stranger@example.com%").count
  end

  test "a refusal with no email says none, and a long email is cut to 254 characters" do
    admit(identity(email: nil))
    assert_equal({ "reason" => "no_account", "issuer_host" => "id.example.com" }, refusals.sole.metadata)

    long = "#{"a" * 300}@example.com"
    admit(identity(email: long, email_verified: false))
    assert_equal 254, refusals.order(:id).last.metadata["email"].length
  end

  test "an open invitation for the email is accepted, with the provider's name" do
    invitation = open_invitation("dana@example.com", groups: [ access_control_groups(:read_only) ])

    result = admit(identity(subject: "sub-dana", email: "Dana@Example.com", name: "Dana from the provider"))

    assert result.ok?, result.errors.inspect
    user = result.record
    assert_equal [ "dana@example.com", "Dana from the provider", ISSUER, "sub-dana" ], user.values_at(:email_address, :name, :sso_issuer, :sso_subject)
    assert_equal [ access_control_groups(:read_only) ], user.groups.to_a
    assert invitation.reload.accepted?
    assert result.accepted_invitation?, "the answer says an invitation was accepted"
    assert_equal "invitation", Audit::Event.find_by!(action: "sso.linked").metadata["via"]
    assert_empty refusals
  end

  test "a lapsed invitation is no invitation" do
    open_invitation("dana@example.com", sent_at: (Invitation::VALID_FOR + 1.day).ago)

    result = admit(identity(email: "dana@example.com"))

    assert_equal [ "no_account" ], result.errors
    assert_not User.exists?(email_address: "dana@example.com")
  end

  test "a verified email of an unlinked account links it" do
    result = admit(identity)

    assert result.ok?, result.errors.inspect
    assert_equal users(:reader), result.record
    assert users(:reader).reload.sso_linked?
    assert_equal "sign_in", Audit::Event.find_by!(action: "sso.linked").metadata["via"]
  end

  test "a start from an invitation with another verified email is a mismatch naming that email, and records nothing" do
    invitation = open_invitation("dana@example.com")
    events = Audit::Event.count

    result = admit(identity(email: "Reader@Example.com"), invitation: invitation)

    assert_equal [ :mismatch, "reader@example.com" ], result.errors
    assert_nil result.record
    assert_equal events, Audit::Event.count
    assert_not users(:reader).reload.sso_linked?
    assert invitation.reload.open?
  end

  test "a start from an invitation with its own email accepts it" do
    invitation = open_invitation("dana@example.com")

    result = admit(identity(subject: "sub-dana", email: "dana@example.com"), invitation: invitation)

    assert result.ok?, result.errors.inspect
    assert_equal invitation.reload.user, result.record
  end

  test "a start from an invitation that has lapsed is no invitation" do
    invitation = open_invitation("dana@example.com", sent_at: (Invitation::VALID_FOR + 1.day).ago)

    result = admit(identity(subject: "sub-dana", email: "dana@example.com"), invitation: invitation)

    assert_equal [ "no_account" ], result.errors
    assert_not User.exists?(email_address: "dana@example.com")
    assert invitation.reload.open?
    assert_equal "no_account", refusals.sole.metadata["reason"]
  end

  test "a start from an invitation whose address now has an unlinked account links that account, as a sign-in" do
    invitation = open_invitation("dana@example.com")
    dana = as(nil) { User.create!(email_address: "dana@example.com", password: "a-long-password-1") }

    result = admit(identity(subject: "sub-dana", email: "dana@example.com"), invitation: invitation)

    assert result.ok?, result.errors.inspect
    assert_equal dana, result.record
    assert_equal "sub-dana", dana.reload.sso_subject
    assert_equal "sign_in", Audit::Event.find_by!(action: "sso.linked").metadata["via"]
    assert_empty Audit::Event.where(action: "invitation.accepted")
  end

  test "a start from an invitation for an owner's address is refused as owner" do
    invitation = Invitation.create!(email_address: "one@example.com", sent_at: Time.current, inviter: users(:one))

    result = admit(identity(email: "one@example.com"), invitation: invitation)

    assert_equal [ "owner" ], result.errors
    assert_not users(:one).reload.sso_linked?
    assert users(:one).authenticate("password")
    assert_equal "owner", refusals.sole.metadata["reason"]
  end

  test "a password that cannot be cleared is no refusal: it raises, nothing is linked and nothing is refused" do
    with_singleton_override(Users::UpdatePassword, :call, ->(*, **) { ApplicationService::Result.failure(nil, [ "Password could not be saved" ]) }) do
      assert_raises(SignIn::Sso::Link::NotCleared) { admit(identity) }
    end

    assert_not users(:reader).reload.sso_linked?
    assert users(:reader).authenticate("password")
    assert_empty refusals
    assert_empty Audit::Event.where(action: "sso.linked")
  end

  test "an identity whose subject another account took meanwhile signs into that account, and the email's account stays unlinked" do
    users(:two).update_columns(sso_issuer: ISSUER, sso_subject: "sub-1", sso_linked_at: 1.day.ago) # version: none (a test's setup)
    # The first look by subject misses, as it would have a moment before the
    # other link was committed: the email then names reader, whose link meets
    # the unique index.
    original = User.method(:linked_to)
    calls = 0
    first_misses = ->(**args) { (calls += 1) == 1 ? User.none : original.call(**args) }

    result = with_singleton_override(User, :linked_to, first_misses) { admit(identity) }

    assert result.ok?, result.errors.inspect
    assert_equal users(:two), result.record
    assert_not users(:reader).reload.sso_linked?
    assert users(:reader).authenticate("password")
    assert_empty Audit::Event.where(action: "sso.linked")
  end
end
