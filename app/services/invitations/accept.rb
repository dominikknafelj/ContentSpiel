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
  #   [:sso_required]  SSO_REQUIRED is set (`SignIn::Oidc.required?`): an
  #               invited person accepts through the provider
  #               (`Invitations::AcceptWithSso`), never with a password.
  #               Answered before the token is read, so it is the one answer
  #               for every token and says nothing of any; `record` is nil.
  # Any other failure is the form's: `errors` are the new user's sentences (a
  # blank, short or unconfirmed password; a name too long), `record` is the
  # invitation, still open, whose `errors` hold the same sentences by the
  # field they belong to (`messages_for(:password)`), so the page can put
  # each under its own field. The invitation is not saved with them.
  #
  # A password in the list of leaked passwords is refused as the model's own
  # rules are (`SignIn::Password::LeakedRule`), with its sentence on the
  # password.
  #
  # THE ORDER. The account is built and judged first, outside the
  # transaction: the model's rules, the confirmation, and then the leak
  # lookup, which is an outside call of up to five seconds and so must not
  # run while the invitation's row is locked (a second press would wait on
  # it). Only then is the row locked and asked again, and the account saved
  # under the lock (`Invitations::Acceptance#accept_into`), so a second press that arrives while the first is in
  # flight reads `:used`. The save validates again. An account made for the
  # address after the row is locked is `:used` (`used?` under the lock, or
  # the unique index); one made in the moment between the first `used?` and
  # the account's judging is refused by the uniqueness rule instead, "Email
  # address has already been taken", and the next press reads `:used`.
  class Accept < ApplicationService
    include Acceptance
    include SignIn::Password::LeakedRule

    # authorize: none (the invitation token is the credential: a token that finds an open invitation is the right to make that one account, and the service acts as the account it makes, as the reset flow does)

    SSO_REQUIRED = :sso_required

    def initialize(token:, name:, password:, password_confirmation:)
      @token = token.to_s
      @name = name
      @password = password.to_s
      @password_confirmation = password_confirmation.to_s
    end

    def call
      return failure(nil, [ SSO_REQUIRED ]) if SignIn::Oidc.required?

      @invitation = Invitation.find_by_token_for(:accept, @token)
      return failure(nil, [ EXPIRED ]) if @invitation.nil?
      return failure(@invitation, [ USED ]) if @invitation.used?

      user = build_user
      return refused(user) if user.errors.any?

      outcome = accept_into(user) do |group_ids|
        record_event("invitation.accepted", subject: @user, field_changes: accepted_changes(group_ids), metadata: { "invitation_id" => @invitation.id })
      end

      case outcome
      when :accepted then success(@user)
      when USED then failure(@invitation, [ USED ])
      else refused(user)
      end
    rescue ActiveRecord::RecordNotFound
      # Withdrawn while this request was on its way.
      failure(nil, [ EXPIRED ])
    rescue ActiveRecord::RecordNotUnique
      # An account was made for the address at the same moment.
      failure(@invitation, [ USED ])
    end

    private

    # The account, unsaved, with the form's sentences in its `errors` when it
    # is refused. As `Users::Save`: a typed password needs a typed
    # confirmation, which `has_secure_password` compares only when it is
    # given; and the leak lookup is asked only of an otherwise valid account.
    def build_user
      user = User.new(email_address: @invitation.email_address, name: @name, password: @password, password_confirmation: @password_confirmation)
      user.validate
      user.errors.add(:password_confirmation, :blank) if @password.present? && @password_confirmation.blank?
      user.errors.add(:password, :leaked) if user.errors.empty? && leaked_password?(user, @password)
      user
    end

    # The form's failure: the account's sentences, and the same sentences on
    # the invitation by the field they belong to.
    def refused(user)
      user.errors.each { |error| @invitation.errors.add(error.attribute, error.full_message) }
      failure(@invitation, user.errors.full_messages)
    end
  end
end
