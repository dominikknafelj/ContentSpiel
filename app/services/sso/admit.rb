module Sso
  # Which account a sign-in provider's identity signs into. An
  # account exists only because an owner invited it: nothing here makes one
  # but an open invitation, and an owner is never matched, linked or signed
  # in, by a link or by an email.
  #
  # THE ORDER, which is the invariant:
  #
  # 1. the account linked to the identity's (issuer, subject): that account,
  #    whatever email the provider gives now (an owner's is refused, `owner`);
  # 2. otherwise an email the provider has not verified is refused
  #    (`email_unverified`);
  # 3. a start from an invitation (`invitation:`) compares the verified email
  #    with that invitation's: another email answers `[:mismatch, email]` and
  #    records nothing, since the person holds the invitation's link and is
  #    shown which address the provider gave; the same email goes on;
  # 4. an account with that email: an owner is refused (`owner`), one linked
  #    under another subject or issuer is refused (`no_account`), any other is
  #    linked (`Sso::Link`) and is the answer;
  # 5. an open invitation for that email, not lapsed, is accepted
  #    (`Invitations::AcceptWithSso`) and its new account is the answer;
  # 6. anything else is refused (`no_account`).
  #
  # WHY AN EMAIL MATCHES ONLY WHILE AN ACCOUNT IS UNLINKED. Once linked, an
  # account is its subject's: the provider vouches for an email, but anyone
  # its directory lets register an address (a second user given the same
  # alias, a recycled mailbox, another tenant of a shared provider) would
  # otherwise take over an account someone else already holds by subject
  # So an email finds an account only the first time, and
  # every later sign-in is by subject alone, which is also how a person whose
  # address changed at the provider still signs in.
  #
  # Emails are compared as `User` and `Invitation` store them (stripped,
  # small letters: `normalizes`).
  #
  # THE AUDIT. Each refusal records `sso.refused` with no actor and no
  # subject (nobody is signed in, and the sentence must not invent anyone),
  # its metadata the reason, the issuer's host and the email the provider
  # gave, cut to 254 characters and left out when there was none. That
  # metadata is the one place the provider's email is kept. A link records
  # `sso.linked` (`Sso::Link`, `Invitations::AcceptWithSso`); a sign-in by
  # an existing link records nothing here (the session's `session.created`
  # is the controller's).
  #
  # RACES. Two callbacks of one person at once, or a subject linked by
  # another request between step 1 and a link: `Sso::Link` locks the
  # account's row and the unique index on (issuer, subject) refuses a second
  # account, so one identity never holds two accounts and an account is never
  # linked twice. When a link or an acceptance loses such a race the match is
  # made once more from step 1, which then finds what won.
  class Admit < ApplicationService
    # authorize: none (the provider's verified identity is the credential, as an invitation's token is)

    MISMATCH = :mismatch
    EMAIL_LIMIT = 254
    # A link or an acceptance lost a race: match again.
    AGAIN = :again
    private_constant :AGAIN

    def initialize(identity, invitation: nil)
      @identity = identity
      @invitation = invitation
      # A refusal is nobody's: whoever is signed in in this browser did not
      # ask the provider for this identity.
      @actor = nil
    end

    def call
      outcome = match
      outcome = match if outcome == AGAIN
      outcome == AGAIN ? refuse("no_account") : outcome
    end

    private

    def match
      linked = User.linked_to(issuer: @identity.issuer, subject: @identity.subject).first
      return linked.owner? ? refuse("owner") : success(linked) if linked
      return refuse("email_unverified") unless @identity.email_verified == true

      email = User.normalize_value_for(:email_address, @identity.email.to_s)
      return refuse("no_account") if email.blank?
      return failure(nil, [ MISMATCH, email ]) if @invitation && @invitation.email_address != email

      account = User.find_by(email_address: email)
      return link(account) if account

      invitation = Invitation.open.find_by(email_address: email)
      return refuse("no_account") if invitation.nil? || invitation.expired?

      accept(invitation)
    end

    def link(account)
      return refuse("owner") if account.owner?
      return refuse("no_account") if account.sso_linked?

      result = Link.call(account, identity: @identity, via: @invitation ? "invitation" : "sign_in")
      return success(result.record) if result.ok?

      case result.errors
      when [ Link::OWNER ] then refuse("owner")
      when [ Link::RACED ] then AGAIN
      else refuse("no_account")
      end
    end

    # An acceptance that finds the invitation used (an account made for the
    # address, or the subject linked, a moment before) looks again; one that
    # lapsed or was withdrawn meanwhile is no invitation.
    def accept(invitation)
      result = Invitations::AcceptWithSso.call(invitation, identity: @identity)
      return success(result.record) if result.ok?

      result.errors == [ Invitations::Acceptance::USED ] ? AGAIN : refuse("no_account")
    end

    def refuse(reason)
      metadata = { "reason" => reason, "issuer_host" => @identity.issuer_host }
      email = User.normalize_value_for(:email_address, @identity.email.to_s)
      metadata["email"] = email.first(EMAIL_LIMIT) if email.present?
      record_event("sso.refused", metadata: metadata, snapshot: nil)
      failure(nil, [ reason ])
    end
  end
end
