module SignIn
  module Passkeys
    # Stores a passkey a person registered on their own account. `registration`
    # is what `SignIn::Passkeys::Registration#verify` answered: a refused one
    # writes nothing. The caller kept the challenge and checked it; this
    # service never sees a request.
    #
    # Only on the actor's own account: a passkey is the person's own device,
    # and nobody adds one for someone else, not even an owner.
    #
    # In one transaction, under the account's row lock:
    # - the passkey;
    # - when the person holds no unused recovery code (their first passkey, or
    #   every code used), a new set of codes, so a passkey never stands without
    #   a way back; the texts are the second half of the result's record, nil
    #   when none were made;
    # - `enrolment_due` cleared on every session of the person, so the session
    #   that enrolled goes on into CS Studio;
    # - `passkey.added`, and `recovery_codes.generated` when codes were made.
    #
    # A linked account (single sign-on) is refused (`denied`), as a stranger's
    # is: its provider is its second factor, and a passkey would be a way in
    # that never asks it (`SignIn::Rules`). Asked again under the row lock, the
    # one `Sso::Link` takes to delete the passkeys, so a link and an add at
    # once never leave a passkey on a linked account.
    #
    # The account mail goes after the commit, to `origin` (the caller's; a
    # service reads no request), and only when mail is ready.
    class Add < ApplicationService
      # authorize: none (the whole rule is "the actor is the user itself", checked in #call; AccessControl has no permission for it, and nobody else may, not even a users.manage holder)

      LINKED = :linked

      def initialize(user, registration:, name:, actor: Current.actor, origin: nil)
        @user = user
        @registration = registration
        @name = name
        @actor = actor
        @origin = origin
      end

      def call
        # Never a token: it acts for its user within a group and has no
        # business with the account's sign-in.
        return denied("users.manage", @user) unless actor.is_a?(User) && actor == @user
        return denied("users.manage", @user) if @user.sso_linked?

        passkey = Passkey.new(user: @user, name: @name)
        return failure(passkey, [ self.class.failed ]) unless @registration&.ok

        passkey.assign_attributes(external_id: @registration.external_id, public_key: @registration.public_key,
          sign_count: @registration.sign_count, transports: @registration.transports)
        return failure(passkey) unless passkey.valid?

        added_at = Time.current
        # A savepoint of its own (`requires_new`), so the unique index's refusal
        # below leaves a caller's own transaction usable.
        codes = Passkey.transaction(requires_new: true) do
          next LINKED if User.lock.find(@user.id).sso_linked?

          passkey.save!
          codes = RecoveryCodes::Generate.new(@user, actor: actor).write_codes(@user, at: added_at) unless @user.recovery_codes.unused.exists?
          @user.sessions.update_all(enrolment_due: false) # version: none (a session is on no public page)

          record_event("passkey.added", subject: passkey, metadata: { "name" => passkey.name })
          record_event("recovery_codes.generated", subject: @user, metadata: { "count" => codes.size, "replaced" => 0 }, snapshot: nil) if codes
          codes
        end

        return denied("users.manage", @user) if codes == LINKED

        ActiveRecord.after_all_transactions_commit do
          SignInMailer.queue_alert(:passkey_added, @user, name: passkey.name, added_at: added_at, origin: @origin)
        end
        success([ passkey, codes ])
      rescue ActiveRecord::RecordNotUnique
        # The credential is stored already (a registration sent twice): the
        # unique index on `external_id` decides, and the add is refused whole.
        failure(Passkey.new(user: @user, name: @name), [ self.class.failed ])
      end

      def self.failed = I18n.t("admin.passkeys.add.failed", raise: true)
    end
  end
end
