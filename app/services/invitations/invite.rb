module Invitations
  # Invites a person who has no account yet (spec "Invites", design answer
  # M4): an `Invitation` row, its groups, and a mail with a link to set a
  # password. No user is made here: accepting makes it (`Invitations::Accept`).
  #
  # REFUSALS, in this order: `users.manage` (and, for a non-owner, only
  # groups they could assign, `Rules#group_refusal`), then mail that is not
  # ready (`MailSettings#ready?`: an invitation whose mail cannot go is one
  # nobody can ever accept), then the address. The address is compared as
  # stored -- `Invitation` and `User` normalise it alike (strip, downcase) --
  # so " Ana@Example.com " finds ana@example.com. An address with an account
  # answers ALREADY_HAS_ACCOUNT; one with an open invitation answers
  # ALREADY_INVITED and leaves that invitation as it was (the dialog offers
  # its Resend). Both sentences are also on `result.record.errors[:email_address]`.
  #
  # The mail is queued after the outer commit (`Rules#queue_mail`). `origin:`
  # is the request's origin, which the mailer uses only where no site address
  # is configured and the environment allows it (`ApplicationMailer#link_origin`).
  # The rate limit (10 invites per person per 3 minutes) is the controller's.
  class Invite < ApplicationService
    include Rules

    ALREADY_HAS_ACCOUNT = "Someone with this address already has an account.".freeze
    ALREADY_INVITED = "This address is already invited.".freeze

    def initialize(email_address:, name: nil, group_ids: [], origin: nil, actor: Current.actor)
      @invitation = Invitation.new(email_address: email_address.to_s, name: name)
      @group_ids = AccessControl::Group.where(id: Array(group_ids).compact_blank).pluck(:id).sort
      @origin = origin
      @actor = actor
    end

    def call
      return denied("users.manage", @invitation) unless authorize!("users.manage", @invitation)

      refusal = group_refusal(@group_ids)
      return refusal if refusal
      return failure(@invitation, [ MAIL_NOT_READY ]) unless MailSettings.current.ready?

      taken = address_taken
      return taken if taken
      return failure(@invitation) unless create

      queue_mail(@invitation, @origin)
      success(@invitation)
    rescue ActiveRecord::RecordNotUnique
      # Two invitations of one address at the same moment: the partial unique
      # index decides, and the second reads as the first's sentence.
      address_taken || raise
    end

    private

    def create
      @invitation.assign_attributes(inviter: actor_user, sent_at: Time.current)

      # A savepoint of its own (`requires_new`), so the `RecordNotUnique` of a
      # racing invitation leaves a caller's outer transaction usable for
      # `address_taken`'s read.
      Invitation.transaction(requires_new: true) do
        @invitation.save || raise(ActiveRecord::Rollback)
        @group_ids.each { |group_id| @invitation.invitation_groups.create!(group_id: group_id) }

        changes = Audit::Snapshot.field_changes_for(@invitation)
        changes["group_ids"] = [ [], @group_ids ] if @group_ids.any?
        record_event("invitation.created", subject: @invitation, field_changes: changes)
        true
      end
    end

    def address_taken
      sentence =
        if User.exists?(email_address: @invitation.email_address) then ALREADY_HAS_ACCOUNT
        elsif Invitation.open.exists?(email_address: @invitation.email_address) then ALREADY_INVITED
        end
      return if sentence.nil?

      @invitation.errors.add(:email_address, sentence)
      failure(@invitation, [ sentence ])
    end
  end
end
