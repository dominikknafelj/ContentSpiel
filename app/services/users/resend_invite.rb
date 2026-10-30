module Users
  # Sends an invited person a new link (design answer M4, "Resend invite"):
  # `invite_sent_at` moves to now, which the invite token is signed over
  # (plan Ruling 3), so the old link dies and the new one works seven more
  # days. The new token is made by `InvitesMailer` in the job, as the first.
  #
  # Needs `users.manage`, and a non-owner may not resend to someone whose
  # groups outrank them (`OwnerProtection#outranked?`, as for any change to
  # a user). Refused for someone with no open invite (`NOT_INVITED`) and while
  # mail is not ready (`Users::Invite::MAIL_NOT_READY`). The row is locked
  # and asked again, so a resend that races an acceptance changes nothing.
  class ResendInvite < ApplicationService
    include OwnerProtection

    NOT_INVITED = "There is no open invite for this person.".freeze

    def initialize(user, origin: nil, actor: Current.actor)
      @user = user
      @origin = origin
      @actor = actor
    end

    def call
      return denied("users.manage", @user) unless authorize!("users.manage", @user)
      return owner_only_denial if owner_protected?
      return denied("users.manage", @user) if outranked?
      return failure(@user, [ NOT_INVITED ]) unless @user.invited?
      return failure(@user, [ Invite::MAIL_NOT_READY ]) unless MailSettings.current.ready?

      resent = User.transaction do
        @user.lock!
        raise ActiveRecord::Rollback unless @user.invited?

        @user.update!(invite_sent_at: Time.current)
        record_event("user.invite_resent", subject: @user, field_changes: Audit::Snapshot.field_changes_for(@user))
        true
      end
      return failure(@user, [ NOT_INVITED ]) unless resent

      # After the commit, as `Users::Invite#queue_mail` says why.
      user, inviter, origin = @user, actor_user, @origin
      ActiveRecord.after_all_transactions_commit do
        ApplicationMailer.queue(InvitesMailer, :invite, user, inviter: inviter, origin: origin)
      end
      success(@user)
    end
  end
end
