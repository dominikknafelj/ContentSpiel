module Invitations
  # Withdraws an invitation (design answer M4, "Withdraw invite"): the row is
  # deleted, with its groups (the join rows cascade), so the link finds
  # nothing and the accept page says "expired". A mail still in the queue is
  # dropped quietly by the job (`MailDeliveryJob`, controller ruling T8a).
  #
  # Only an OPEN invitation: an accepted one is history, its account the
  # user's own (deleting that is `Users::Destroy`). The row is locked and
  # asked again, so a withdrawal that races an acceptance deletes nothing.
  #
  # Needs `users.manage`, and a non-owner may not withdraw an invitation into
  # groups that outrank them (`Rules#outranked?`). The event is recorded
  # before the delete, in its transaction, as `user.deleted` is: the subject's
  # label keeps the address once the row is gone.
  class Withdraw < ApplicationService
    include Rules

    def initialize(invitation, actor: Current.actor)
      @invitation = invitation
      @actor = actor
    end

    def call
      return denied("users.manage", @invitation) unless authorize!("users.manage", @invitation)
      return denied("users.manage", @invitation) if outranked?
      return failure(@invitation, [ NOT_OPEN ]) unless @invitation.open?

      withdrawn = Invitation.transaction do
        @invitation.lock!
        raise ActiveRecord::Rollback unless @invitation.open?

        record_event("invitation.withdrawn", subject: @invitation)
        @invitation.destroy!
        true
      end
      withdrawn ? success(@invitation) : failure(@invitation, [ NOT_OPEN ])
    rescue ActiveRecord::RecordNotFound
      # Withdrawn by someone else a moment before: it is gone either way.
      failure(@invitation, [ NOT_OPEN ])
    end
  end
end
