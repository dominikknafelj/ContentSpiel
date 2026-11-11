module RecoveryCodes
  # A new set of a person's recovery codes: every code they held, used or
  # not, is deleted, and RecoveryCode::COUNT new ones are stored as digests
  # with one `generated_at`. The texts are the result's record, for the one
  # screen that shows them; they are kept nowhere and reach no event.
  #
  # Only on the actor's own account: the codes are shown to whoever makes
  # them, so nobody makes them for someone else, not even an owner.
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

      codes = RecoveryCode.transaction do
        # The account's row lock: two sets made at once would leave the
        # person holding texts that the other set's delete took away.
        User.lock.find(@user.id)
        replaced = @user.recovery_codes.unused.count
        codes = write_codes(@user, at: Time.current)
        record_event("recovery_codes.generated", subject: @user, metadata: { "count" => codes.size, "replaced" => replaced }, snapshot: nil)
        codes
      end
      success(codes)
    end

    # The set's writes alone, with no authorization and no event, for a
    # caller that has authorized and records its own (`Passkeys::Add`, in
    # its transaction). Answers the texts as they are shown.
    def write_codes(user, at:)
      texts = RecoveryCode.texts
      RecoveryCode.where(user_id: user.id).delete_all # version: none (recovery codes are on no public page)
      RecoveryCode.insert_all(texts.map { |text| { user_id: user.id, digest: RecoveryCode.digest(text), generated_at: at } }) # version: none (recovery codes are on no public page)
      texts
    end
  end
end
