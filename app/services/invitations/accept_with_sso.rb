module Invitations
  # An open invitation accepted through the site's sign-in provider:
  # `Sso::Admit` calls it once the provider's verified email is the
  # invitation's. The account is made as `Invitations::Accept` makes it (the
  # invitation's address and groups, `Invitations::Acceptance`), but linked
  # from the start: the provider's issuer and subject, a password nobody
  # holds (`User.unusable_password`, never shown or kept) and the name the
  # provider gave, cut to a user's limit, or none. `invitation.accepted` and
  # `sso.linked` (`via: "invitation"`) are recorded in the one transaction,
  # both as the new account. Nothing is typed, so nothing is looked up in
  # the list of leaked passwords.
  #
  # THE IDENTITY IS THE CREDENTIAL, as the token is `Accept`'s: whoever is
  # signed in in this browser is not who accepts. So the identity is checked
  # here again, whatever the caller decided: its email must be verified and
  # be the invitation's, or nothing is made (`[:mismatch]`).
  #
  # THE ANSWERS are `Accept`'s: `[:expired]` for an invitation that lapsed or
  # was withdrawn meanwhile, `[:used]` for one accepted, or whose address has
  # an account, under the row's lock; and `[:used]` too when the unique
  # indexes refuse the account at the same moment (the address, or the
  # provider's subject, which another account now holds), so a caller that
  # looks again finds the account that won.
  class AcceptWithSso < ApplicationService
    include Acceptance

    # authorize: none (the provider's verified identity is the credential, as an invitation's token is Accept's: an identity whose verified email is an open invitation's is the right to make that one account, and the service acts as the account it makes)

    MISMATCH = :mismatch

    def initialize(invitation, identity:)
      @invitation = invitation
      @identity = identity
    end

    def call
      return failure(@invitation, [ MISMATCH ]) unless @identity.email_verified == true && invited_email?
      return failure(@invitation, [ EXPIRED ]) if @invitation.expired?
      return failure(@invitation, [ USED ]) if @invitation.used?

      user = build_user
      outcome = accept_into(user) do
        record_event("sso.linked", subject: user, snapshot: nil, metadata: {
          "via" => "invitation", "issuer_host" => @identity.issuer_host, "passkeys_removed" => 0, "recovery_codes_removed" => 0
        })
      end

      case outcome
      when :accepted then success(@user)
      when USED then failure(@invitation, [ USED ])
      else failure(@invitation, user.errors.full_messages)
      end
    rescue ActiveRecord::RecordNotFound
      failure(@invitation, [ EXPIRED ])
    rescue ActiveRecord::RecordNotUnique
      failure(@invitation, [ USED ])
    end

    private

    def invited_email? = User.normalize_value_for(:email_address, @identity.email.to_s) == @invitation.email_address

    def build_user
      User.new(email_address: @invitation.email_address, name: @identity.name.to_s.strip.first(User::NAME_LIMIT),
        password: User.unusable_password, sso_issuer: @identity.issuer, sso_subject: @identity.subject, sso_linked_at: Time.current)
    end
  end
end
