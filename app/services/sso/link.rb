module Sso
  # Links an account to the provider's subject: from now
  # on the account signs in through the provider alone. In one transaction,
  # under the account's row lock:
  #
  # - the issuer, the subject and the time are written;
  # - the password becomes one nobody holds, through
  #   `Users::UpdatePassword` (`clear: true`), which ends every session of
  #   the account (one `session.ended`, `password_changed`) and records
  #   `user.updated` with its credentials marker and the link's columns. The
  #   new digest also voids every reset link issued before, since a reset
  #   token is signed over the digest's salt;
  # - the passkeys and the recovery codes are deleted: the provider is the
  #   account's second factor now, and a passkey left behind would be a way
  #   in that never asks the provider;
  # - `sso.linked` is recorded, with how many of each went.
  #
  # Called by `Sso::Admit` alone, once the provider's verified identity has
  # matched this account; the actor is the account itself, whom the
  # provider has just proved, as the reset flow acts as the user its token
  # names.
  #
  # TWICE NEVER. An owner is refused (`[:owner]`): owners keep a password and
  # a passkey, and no outside service stands in for them. Under the lock the
  # account is read again: already linked to this identity, it is answered as
  # it is, with nothing written (two callbacks of one sign-in at once); linked
  # to another, it is refused (`[:linked]`). A subject that another account
  # holds is refused by the unique index on (issuer, subject), the whole
  # transaction rolled back (`[:raced]`): the caller looks again and finds
  # that account.
  #
  # A password that cannot be cleared is no refusal of the identity: it
  # raises `NotCleared` (`Users::UpdatePassword`'s sentences, which carry no
  # value) and the transaction rolls back whole, so it is never told as
  # "no invited account". Either way the account object the caller holds is
  # read again, holding no link that was rolled back.
  class Link < ApplicationService
    # authorize: none (called by Sso::Admit once the provider's verified identity matched this account; the identity is the credential and the service acts as the account it proves)

    VIA = %w[sign_in invitation].freeze

    OWNER = :owner
    LINKED = :linked
    RACED = :raced

    class NotCleared < StandardError; end

    def initialize(user, identity:, via:, actor: user)
      raise ArgumentError, "via is one of #{VIA.join(", ")}, not #{via.inspect}" unless VIA.include?(via)

      @user = user
      @identity = identity
      @via = via
      @actor = actor
    end

    def call
      return failure(@user, [ OWNER ]) if @user.owner?

      outcome = User.transaction do
        @user.lock!
        next OWNER if @user.owner?
        next :already if @user.sso_issuer == @identity.issuer && @user.sso_subject == @identity.subject
        next LINKED if @user.sso_linked?

        @user.assign_attributes(sso_issuer: @identity.issuer, sso_subject: @identity.subject, sso_linked_at: Time.current)
        cleared = Users::UpdatePassword.call(@user, clear: true, keep_acting_session: false, actor: actor)
        raise NotCleared, "the password of user #{@user.id} was not cleared: #{cleared.errors.join(" ")}" unless cleared.ok?

        passkeys = Passkey.where(user_id: @user.id).delete_all # version: none (passkeys are on no public page)
        codes = RecoveryCode.where(user_id: @user.id).delete_all # version: none (recovery codes are on no public page)
        record_event("sso.linked", subject: @user, snapshot: nil, metadata: {
          "via" => @via, "issuer_host" => @identity.issuer_host, "passkeys_removed" => passkeys, "recovery_codes_removed" => codes
        })
        :done
      end

      case outcome
      when :done, :already then success(@user)
      else failure(@user, [ outcome ])
      end
    rescue ActiveRecord::RecordNotUnique
      @user.reload
      failure(@user, [ RACED ])
    rescue NotCleared
      @user.reload
      raise
    end
  end
end
