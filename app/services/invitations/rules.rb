module Invitations
  # What the invitation services share. An invitation is no user, so the
  # user services' owner rules (`Users::OwnerProtection`) do not apply: an
  # invitation is never an owner and has no account to take over. What does
  # apply is the groups: accepting puts the person into the invitation's
  # groups, which hands them their grants. So, as `Users::Save` asks of a
  # user's groups,
  #
  # - a non-owner may invite only into groups they could manage as they stand
  #   (`AccessControl.can_manage_group?`, the test `Users::Save` makes), and
  # - a non-owner may not resend or withdraw an invitation into a group they
  #   could not manage (the invitation's `outranked?`, as a user's is in
  #   `Users::Manageability`).
  #
  # An owner, or a trusted code path, is waved through (`actor_owner?`, the
  # users side's own answer, so the two cannot disagree on who an owner is).
  module Rules
    MAIL_NOT_READY = "Invites need mail.".freeze
    NOT_OPEN = "There is no open invite for this person.".freeze

    private

    def actor_owner? = Users::Manageability.actor_owner?(actor)

    def group_refusal(group_ids)
      return if group_ids.empty? || actor_owner?

      AccessControl::Group.includes(:grants).where(id: group_ids).order(:name).each do |group|
        next if AccessControl.can_manage_group?(actor, group)

        return denied("users.manage", @invitation, message: "You don't have permission to add users to the #{group.name} group")
      end
      nil
    end

    def outranked?
      return false if actor_owner? || actor.nil?

      AccessControl::Group.includes(:grants).where(id: @invitation.invitation_groups.select(:group_id)).any? do |group|
        !AccessControl.can_manage_group?(actor, group)
      end
    end

    # The mail is queued when the write is committed, not before: inside a
    # caller's transaction `after_all_transactions_commit` waits for its
    # commit and sends nothing if it rolls back (this app enqueues at once
    # otherwise: `enqueue_after_transaction_commit` is not on). Outside one
    # it runs now. The token is made by `InvitesMailer` in the job: no token
    # is an argument of a mailer or a job.
    def queue_mail(invitation, origin)
      ActiveRecord.after_all_transactions_commit do
        ApplicationMailer.queue(InvitesMailer, :invite, invitation, origin: origin)
      end
    end
  end
end
