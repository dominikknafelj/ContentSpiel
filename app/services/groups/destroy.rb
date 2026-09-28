module Groups
  # Deletes a group (access-control design spec §3.2 "On group delete the
  # token is revoked; the delete confirmation says so", §5 "Groups
  # module"). Needs `groups.manage`; built-in groups can't be deleted (the
  # four seeded ones every other part of the app looks up by name).
  #
  # Every token scoped to the group is revoked first, through
  # `ApiTokens::Revoke` -- one `token.revoked` event each, so the log says
  # which assistants stopped working and why (`"reason" => "group
  # deleted"`). Deleting the group is what authorizes that: someone with
  # `groups.manage` but not `tokens.manage` may still delete a group other
  # people's tokens use (`ApiTokens::Revoke`'s `group_deleted:`).
  #
  # Then the token rows themselves go. `api_tokens.group_id` is not null
  # (design spec §3.2), so a token -- even one revoked long ago -- can't
  # outlive its group. A revoked token authenticates nothing, and what it
  # was stays in the log (its `token.issued`/`token.revoked` snapshots);
  # only its row in the "AI assistant" list disappears.
  #
  # All in one transaction: a failure anywhere leaves every token active
  # and the group in place.
  class Destroy < ApplicationService
    def initialize(group, actor: Current.actor)
      @group = group
      @actor = actor
    end

    def call
      return denied("groups.manage", @group) unless authorize!("groups.manage", @group)
      return built_in_refusal if @group.built_in?

      destroyed = AccessControl::Group.transaction do
        @group.api_tokens.active.find_each do |token|
          ApiTokens::Revoke.call(token, actor: actor, group_deleted: true).ok? || raise(ActiveRecord::Rollback)
        end
        ApiToken.where(group_id: @group.id).delete_all

        record_event("group.deleted", subject: @group)
        @group.destroy || raise(ActiveRecord::Rollback)
      end
      return failure(@group) unless destroyed

      success(@group)
    end

    private

    def built_in_refusal
      @group.errors.add(:base, "Built-in groups can't be deleted")
      failure(@group, [ "Built-in groups can't be deleted" ])
    end
  end
end
