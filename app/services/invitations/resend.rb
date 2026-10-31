module Invitations
  # Sends an invited person a new link (design answer M4, "Resend invite"):
  # `sent_at` moves to now, which the token is signed over, so the old link
  # dies and the new one works seven more days. The new token is made by
  # `InvitesMailer` in the job, as the first.
  #
  # Needs `users.manage`, and a non-owner may not resend an invitation into
  # groups that outrank them (`Rules#outranked?`). Refused for an invitation
  # that is no longer open (`NOT_OPEN`) and while mail is not ready. The row
  # is locked and asked again, so a resend that races an acceptance changes
  # nothing.
  class Resend < ApplicationService
    include Rules

    def initialize(invitation, origin: nil, actor: Current.actor)
      @invitation = invitation
      @origin = origin
      @actor = actor
    end

    def call
      return denied("users.manage", @invitation) unless authorize!("users.manage", @invitation)
      return denied("users.manage", @invitation) if outranked?
      return failure(@invitation, [ NOT_OPEN ]) unless @invitation.open?
      return failure(@invitation, [ MAIL_NOT_READY ]) unless MailSettings.current.ready?

      resent = Invitation.transaction do
        @invitation.lock!
        raise ActiveRecord::Rollback unless @invitation.open?

        @invitation.update!(sent_at: Time.current)
        record_event("invitation.resent", subject: @invitation, field_changes: Audit::Snapshot.field_changes_for(@invitation))
        true
      end
      return failure(@invitation, [ NOT_OPEN ]) unless resent

      queue_mail(@invitation, @origin)
      success(@invitation)
    end
  end
end
