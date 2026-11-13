require "test_helper"

# `Sso::Unlink`: an owner (or the console) takes a link away. The person is
# signed out everywhere, and is mailed a reset link, since the password the
# link left is one nobody holds.
class Sso::UnlinkTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  ISSUER = "https://id.example.com/oauth2/default".freeze

  setup do
    @user = users(:reader)
    @user.update_columns(sso_issuer: ISSUER, sso_subject: "sub-1", sso_linked_at: 1.day.ago) # version: none (a test's setup)
    2.times { Session.start(user: @user, method: "sso", user_agent: nil, ip_address: nil) }
    put_mail_state(:working)
  end

  def unlink(actor:, user: @user, channel: :admin) = as(actor, channel:) { Sso::Unlink.call(user, actor:, origin: "http://localhost:3000") }

  def queued = { fingerprint: MailSettings.current.fingerprint }

  test "an owner unlinks: the columns clear, every session ends as sso_unlinked, sso.unlinked is recorded and the reset mail is queued" do
    result = nil
    assert_enqueued_email_with PasswordsMailer, :reset, params: queued, args: [ @user, { origin: "http://localhost:3000" } ] do
      result = unlink(actor: users(:one))
    end

    assert result.ok?, result.errors.inspect
    @user.reload
    assert_equal [ nil, nil, nil ], @user.values_at(:sso_issuer, :sso_subject, :sso_linked_at)
    assert_empty @user.sessions
    ended = Audit::Event.find_by!(action: "session.ended")
    assert_equal [ @user, users(:one).id ], [ ended.subject, ended.user_id ]
    assert_equal({ "reason" => "sso_unlinked", "count" => 2 }, ended.metadata)
    unlinked = Audit::Event.find_by!(action: "sso.unlinked")
    assert_equal [ users(:one), @user ], [ unlinked.actor, unlinked.subject ]
    assert_equal({ "issuer_host" => "id.example.com" }, unlinked.metadata)
  end

  test "a non-owner is denied and nothing changes" do
    result = nil
    assert_no_enqueued_emails do
      result = unlink(actor: users(:two))
    end

    assert result.denied?
    assert_equal [ ISSUER, "sub-1" ], @user.reload.values_at(:sso_issuer, :sso_subject)
    assert_equal 2, @user.sessions.count
    assert_empty Audit::Event.where(action: %w[sso.unlinked session.ended])
    assert_equal 1, Audit::Event.where(action: "access.denied").count
  end

  test "the console may unlink" do
    result = unlink(actor: nil, channel: :console)

    assert result.ok?, result.errors.inspect
    assert_not @user.reload.sso_linked?
    assert_nil Audit::Event.find_by!(action: "sso.unlinked").actor_id
  end

  test "an unlinked user is a failure with no event and no mail" do
    assert unlink(actor: users(:one)).ok?
    events = Audit::Event.count

    result = nil
    assert_no_enqueued_emails do
      result = unlink(actor: users(:one), user: @user.reload)
    end

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "#{@user.name_or_email} is not linked to single sign-on." ], result.errors
    assert_equal events, Audit::Event.count
  end

  test "without mail ready the link still goes, and no mail is queued" do
    put_mail_state(:not_set_up)

    assert_no_enqueued_emails do
      assert unlink(actor: users(:one)).ok?
    end
    assert_not @user.reload.sso_linked?
  end
end
