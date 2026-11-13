module SignIn
  module Passkeys
    # Renames one of the actor's own passkeys. A blank or overlong name is the
    # model's refusal; the same name again writes and records nothing.
    # `passkey.renamed` carries the name before and after in `field_changes`.
    class Rename < ApplicationService
      # authorize: none (the whole rule is "the actor is the passkey's own user", checked in #call; AccessControl has no permission for it, and nobody else may, not even a users.manage holder)

      def initialize(passkey, name:, actor: Current.actor)
        @passkey = passkey
        @name = name
        @actor = actor
      end

      def call
        user = @passkey.user
        return denied("users.manage", user) unless actor.is_a?(User) && actor == user

        @passkey.name = @name
        return failure(@passkey) unless @passkey.valid?
        return success(@passkey) unless @passkey.changed?

        Passkey.transaction do
          @passkey.save!
          record_event("passkey.renamed", subject: @passkey, field_changes: Audit::Snapshot.field_changes_for(@passkey))
        end
        success(@passkey)
      end
    end
  end
end
