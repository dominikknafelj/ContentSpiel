module Invitations
  # The invited person sets a password through the link (design answer M5):
  # the account is CREATED here -- the invitation's address, the typed name
  # and password, the invitation's groups -- and the invitation is marked
  # accepted (`accepted_at`, `user`). Signing them in is the controller's (it
  # holds the request).
  #
  # THE TOKEN IS THE CREDENTIAL. Whoever is signed in in this browser, if
  # anyone, is not who accepts: the actor is the user the token makes, and
  # the event (`invitation.accepted`, its subject the new user) is theirs, as
  # the reset flow passes `actor: user` to `Users::UpdatePassword`. So there
  # is no permission to ask: a token that finds an open invitation IS the
  # right to make that one account, and nothing else.
  #
  # THE ANSWERS (plan Ruling 3). A refusal of the link is a symbol in
  # `result.errors`, which the page turns into its own words:
  #   [:expired]  the token finds no invitation: lapsed, resent since (the old
  #               link), withdrawn (the row is gone) or never valid -- one
  #               answer, so the page does not say whether an invitation
  #               existed (M5); `record` is nil.
  #   [:used]     the token finds an invitation that was accepted (accepting
  #               keeps `sent_at`, so a used link still finds its row), or
  #               whose address has had an account made for it since (the
  #               New user form): either way the person signs in. `record` is
  #               the invitation.
  # Any other failure is the form's: `errors` are the new user's sentences (a
  # blank, short or unconfirmed password; a name too long), `record` is the
  # invitation, still open.
  #
  # The row is locked and asked again before anything is written, so a second
  # press that arrives while the first is in flight reads `:used`.
  class Accept < ApplicationService
    # authorize: none (the invitation token is the credential: a token that finds an open invitation is the right to make that one account, and the service acts as the account it makes, as the reset flow does)

    EXPIRED = :expired
    USED = :used

    def initialize(token:, name:, password:, password_confirmation:)
      @token = token.to_s
      @name = name
      @password = password.to_s
      @password_confirmation = password_confirmation.to_s
    end

    def call
      @invitation = Invitation.find_by_token_for(:accept, @token)
      return failure(nil, [ EXPIRED ]) if @invitation.nil?
      return failure(@invitation, [ USED ]) if @invitation.used?

      outcome = Invitation.transaction do
        @invitation.lock!
        next USED if @invitation.used?
        next :invalid unless (@user = create_user)

        # From here on everything is recorded as the new account's.
        @actor = @user
        group_ids = @invitation.invitation_groups.pluck(:group_id).sort
        # Through `Membership` itself, as `Users::Save#sync_groups`, so its
        # `after_commit` drops the memoised grants.
        group_ids.each { |group_id| AccessControl::Membership.create!(user: @user, group_id: group_id) }
        @invitation.update!(accepted_at: Time.current, user: @user)

        changes = Audit::Snapshot.field_changes_for(@user)
        changes["group_ids"] = [ [], group_ids ] if group_ids.any?
        record_event("invitation.accepted", subject: @user, field_changes: changes, metadata: { "invitation_id" => @invitation.id })
        :accepted
      end

      case outcome
      when :accepted then success(@user)
      when USED then failure(@invitation, [ USED ])
      else failure(@invitation, @user_errors)
      end
    rescue ActiveRecord::RecordNotFound
      # Withdrawn while this request was on its way.
      failure(nil, [ EXPIRED ])
    rescue ActiveRecord::RecordNotUnique
      # An account was made for the address at the same moment.
      failure(@invitation, [ USED ])
    end

    private

    # The account, or nil with the form's sentences in `@user_errors`. As
    # `Users::Save`: a typed password needs a typed confirmation, which
    # `has_secure_password` compares only when it is given.
    def create_user
      user = User.new(email_address: @invitation.email_address, name: @name, password: @password, password_confirmation: @password_confirmation)
      user.validate
      user.errors.add(:password_confirmation, :blank) if @password.present? && @password_confirmation.blank?
      if user.errors.any? || !user.save
        @user_errors = user.errors.full_messages
        return nil
      end
      user
    end
  end
end
