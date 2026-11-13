module RecoveryCodes
  # A new set of a person's recovery codes: every code they held, used or
  # not, is deleted, and RecoveryCode::COUNT new ones are stored as digests
  # with one `generated_at`. The texts are the result's record, for the one
  # screen that shows them; they are kept nowhere and reach no event.
  #
  # Only on the actor's own account: the codes are shown to whoever makes
  # them, so nobody makes them for someone else, not even an owner.
  #
  # Only for a person who holds a passkey: codes are a backup for passkeys
  # (removing the last passkey deletes them, `SignIn::Passkeys::Remove`). Alone they
  # would be the account's only second factor (`User#second_factor?`), so
  # every sign-in would ask for one and spend it. Read under the row lock,
  # so a passkey removed at the same moment cannot leave a fresh set behind.
  #
  # Never for a linked account (single sign-on): its provider is its second
  # factor (`SignIn::Rules`), and `Sso::Link` deleted its passkeys and codes.
  # Refused as a stranger's is; a link landing meanwhile is caught by the
  # passkey check under the lock, since the link deletes the passkeys under
  # the same row lock.
  #
  # `recovery_codes.generated` carries how many unused codes the new set
  # replaced, never a code or a digest.
  class Generate < ApplicationService
    # authorize: none (the whole rule is "the actor is the user itself", checked in #call; AccessControl has no permission for it, and nobody else may, not even a users.manage holder)

    def initialize(user, actor: Current.actor)
      @user = user
      @actor = actor
    end

    def call
      # Never a token: it acts for its user within a group and has no
      # business with the account's sign-in.
      return denied("users.manage", @user) unless actor.is_a?(User) && actor == @user
      return denied("users.manage", @user) if @user.sso_linked?

      codes = RecoveryCode.transaction do
        # The account's row lock: two sets made at once would leave the
        # person holding texts that the other set's delete took away.
        User.lock.find(@user.id)
        next unless @user.passkeys.exists?

        replaced = @user.recovery_codes.unused.count
        codes = write_codes(@user, at: Time.current)
        record_event("recovery_codes.generated", subject: @user, metadata: { "count" => codes.size, "replaced" => replaced }, snapshot: nil)
        codes
      end
      return failure(@user, [ self.class.passkey_first ]) unless codes

      success(codes)
    end

    def self.passkey_first = I18n.t("admin.recovery_codes.generate.passkey_first", raise: true)

    # The set's writes alone, with no authorization and no event, for a
    # caller that has authorized and records its own (`SignIn::Passkeys::Add`, in
    # its transaction). Answers the texts as they are shown.
    def write_codes(user, at:)
      texts = RecoveryCode.texts
      RecoveryCode.where(user_id: user.id).delete_all # version: none (recovery codes are on no public page)
      RecoveryCode.insert_all(texts.map { |text| { user_id: user.id, digest: RecoveryCode.digest(text), generated_at: at } }) # version: none (recovery codes are on no public page)
      texts
    end
  end
end
