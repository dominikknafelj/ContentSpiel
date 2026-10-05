module Admin
  module GroupsScreen
    # The group editor's delete zone (round 3 Task 11, handoff §10 C37), below the
    # form: what deleting costs in words, the trigger, and the confirm dialog that
    # names the AI tokens `Groups::Destroy` will revoke.
    #
    # - The trigger is `danger_text` (a secondary button whose label alone is red:
    #   the trigger of a destructive action outside a dialog); the red solid
    #   "Delete group" is the dialog's confirm alone.
    # - A built-in group (the four seeded ones, which the app looks up by name)
    #   shows "A built-in group can be changed but not deleted." instead.
    # - The caller passes the counts and the ACTIVE tokens, loaded once (grouped /
    #   preloaded queries): a token is named "<token name> — <user>", never any
    #   part of its secret, and a revoked one isn't listed because deleting the
    #   group revokes nothing about it. The list is bounded (`MAX_TOKENS_SHOWN`
    #   names, then "and N more") so a group with a great many tokens can't make
    #   the dialog huge.
    # - The dialog's form DELETEs the group. The zone is rendered AFTER the group
    #   form, never inside it (forms don't nest); `Groups::Destroy` decides again.
    class DeleteZoneComponent < AdminComponent
      MAX_TOKENS_SHOWN = 10

      def initialize(group:, member_count:, tokens:, url_options: {})
        @group = group
        @member_count = member_count
        @tokens = tokens
        @url_options = url_options
      end

      private

      attr_reader :group, :member_count, :tokens, :url_options

      def dialog_id = "delete-group-#{group.id}"
      def token_count = tokens.size
      def shown_tokens = tokens.first(MAX_TOKENS_SHOWN)
      def hidden_tokens = token_count - shown_tokens.size

      def members_effect
        case member_count
        when 0 then "It has no members."
        when 1 then "1 member loses its permissions."
        else "#{member_count} members lose its permissions."
        end
      end

      def tokens_effect
        case token_count
        when 0 then "It has no AI tokens."
        when 1 then "1 AI token is revoked."
        else "#{token_count} AI tokens are revoked."
        end
      end

      def dialog_body
        members = member_count.zero? ? "It has no members" : "Its #{helpers.pluralize(member_count, "member")} #{member_count == 1 ? "loses" : "lose"} these permissions"
        tokens_clause = token_count.zero? ? "" : ", and its #{helpers.pluralize(token_count, "AI token")} #{token_count == 1 ? "is" : "are"} revoked"
        "#{members}#{tokens_clause}. Users themselves are not deleted."
      end
    end
  end
end
