module Sso
  # Takes an account's link to the sign-in provider away: an owner's act from
  # the user editor, or the console's (the way back for a linked account when
  # the provider is gone). Owner-only, as the owner zone's other actions: a
  # link decides how a person signs in at all.
  #
  # In one transaction, under the account's row lock: the three columns are
  # cleared, every session of the account ends (one `session.ended`,
  # `sso_unlinked`, with the count; a session made through the provider must
  # not outlive the link it stood on), and `sso.unlinked` is recorded. The
  # password is still the one nobody holds that the link left, so after the
  # commit the person is mailed an ordinary reset link (`PasswordsMailer#reset`,
  # `origin:` as the reset request's), when mail is ready; without mail an
  # owner tells them to ask for a reset themselves. Their passkeys and codes
  # went with the link and do not come back.
  #
  # `#mailed?` says whether the mail was queued, read after `#call`: the
  # caller's words must never promise a mail that is not sent (the owner's
  # toast, `Admin::SsoLinksController`). Mail readiness is asked once, here,
  # and the answer is both what is queued and what is said.
  #
  # An account with no link is a failure, with no event and no mail.
  class Unlink < ApplicationService
    # authorize: none (owner-only, asked through Users::Manageability.actor_owner? in #call as Sessions::EndAll asks it; no AccessControl permission says "owner")

    def self.not_linked(user) = I18n.t("admin.users.sso.not_linked", name: user.name_or_email, raise: true)

    def initialize(user, actor: Current.actor, origin: nil)
      @user = user
      @actor = actor
      @origin = origin
      @mailed = false
    end

    def mailed? = @mailed

    def call
      return denied("users.manage", @user) unless Users::Manageability.actor_owner?(actor)
      return failure(@user, [ self.class.not_linked(@user) ]) unless @user.sso_linked?

      unlinked = User.transaction do
        @user.lock!
        next false unless @user.sso_linked?

        issuer = @user.sso_issuer
        @user.update!(sso_issuer: nil, sso_subject: nil, sso_linked_at: nil)
        ended = @user.sessions.destroy_each_locked
        # No snapshot: the link is the event's own.
        record_event("session.ended", subject: @user, metadata: { "reason" => "sso_unlinked", "count" => ended }, snapshot: nil) if ended.positive?
        record_event("sso.unlinked", subject: @user, metadata: { "issuer_host" => SignIn::Oidc.issuer_host(issuer) }, snapshot: nil)
        true
      end
      return failure(@user, [ self.class.not_linked(@user) ]) unless unlinked

      queue_reset
      success(@user)
    end

    private

    # After the outer commit, as the invitation mails are (`Invitations::Rules#queue_mail`).
    def queue_reset
      return unless MailSettings.current.ready?

      @mailed = true
      ActiveRecord.after_all_transactions_commit do
        ApplicationMailer.queue(PasswordsMailer, :reset, @user, **{ origin: @origin }.compact)
      end
    end
  end
end
