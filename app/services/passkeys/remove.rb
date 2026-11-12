module Passkeys
  # Removes one of the actor's own passkeys.
  #
  # A person the policy covers keeps at least one: their last is refused,
  # with nothing written and nothing recorded, whether the screen or a
  # crafted request asked. The policy and the count are read under the
  # account's row lock, so two removals at once cannot both pass for the
  # last two.
  #
  # The last passkey of a person the policy does not cover goes with their
  # recovery codes, so the account is back to its password alone, as the
  # dialog says. `passkey.removed` names the passkey and how many codes went.
  class Remove < ApplicationService
    # authorize: none (the whole rule is "the actor is the passkey's own user", checked in #call; AccessControl has no permission for it, and nobody else may, not even a users.manage holder)

    def initialize(passkey, actor: Current.actor)
      @passkey = passkey
      @actor = actor
    end

    def call
      user = @passkey.user
      return denied("users.manage", user) unless actor.is_a?(User) && actor == user

      removed = Passkey.transaction do
        User.lock.find(user.id)
        last = !user.passkeys.where.not(id: @passkey.id).exists?
        raise ActiveRecord::Rollback if last && Policy.current.covers?(user)

        codes = last ? RecoveryCode.where(user_id: user.id).delete_all : 0 # version: none (recovery codes are on no public page)
        record_event("passkey.removed", subject: @passkey, metadata: { "name" => @passkey.name, "recovery_codes_removed" => codes })
        @passkey.destroy!
        true
      end
      return failure(@passkey, [ self.class.last_required ]) unless removed

      success(@passkey)
    end

    def self.last_required = I18n.t("admin.passkeys.remove.last_required", raise: true)
  end
end
