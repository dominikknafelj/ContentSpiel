module Invitations
  # An account made for an invited address closes that address's open
  # invitation (the review of the rework, Important 1). Without it: invite
  # dana@, an owner makes her account on the New user form, later deletes it,
  # and the old link (within its seven days) would make a new account in the
  # invitation's groups and sign the person in.
  #
  # THE SEAM is the audit log's after-commit notification
  # (`Audit::NOTIFICATION`, "audit.content_spiel"), the one `Editing::Signals`
  # hears (`config/initializers/invitations.rb`): users stay unaware of
  # invitations, so neither `Users::Save` nor a database trigger knows of
  # this. It hears `user.created`, and `user.updated` when the address
  # changed (an existing account moved onto an invited address). It runs
  # after the user's write has committed, so it can never undo it, and
  # `heard` never raises: a failure here is logged by its class and reported,
  # and the invitation's link still answers "used" while the account exists
  # (`Invitation#used?`), which is what `Invitations::Accept` keeps.
  #
  # The delete is not audited: the account's own event is the record of why,
  # and an invitation that can no longer be accepted is nothing anybody did.
  module Accounts
    ACTIONS = %w[user.created user.updated].freeze

    module_function

    def heard(event)
      return unless ACTIONS.include?(event.action) && event.subject_type == "User"
      return if event.action == "user.updated" && !event.field_changes.to_h.key?("email_address")

      address = User.where(id: event.subject_id).pick(:email_address)
      return if address.nil?

      Invitation.open.where(email_address: address).delete_all # version: none (an invitation is no public content)
    rescue StandardError => error
      Rails.logger.warn("Open invitation not closed for a new account: #{error.class}")
      Rails.error.report(error, handled: true)
    end
  end
end
