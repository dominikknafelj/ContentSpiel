module Admin
  module GroupsScreen
    # The group editor's delete zone, after the form: the shared action zone
    # saying what deleting costs, its trigger, and the confirm dialog that
    # names the AI tokens `Groups::Destroy` will revoke.
    #
    # - The trigger is `danger_text` (a secondary button whose label alone is
    #   red: the trigger of a destructive action outside a dialog); the red
    #   solid "Delete group" is the dialog's confirm alone.
    # - A built-in group (the four seeded ones, which the app looks up by
    #   name) shows a neutral notice in the zone's place, saying it can be
    #   changed but not deleted.
    # - The caller passes the counts and the ACTIVE tokens, loaded once
    #   (grouped / preloaded queries): a token is named "<token name> —
    #   <user>", never any part of its secret, and a revoked one isn't listed
    #   because deleting the group revokes nothing about it. The list is
    #   bounded (`MAX_TOKENS_SHOWN` names, then "and N more") so a group with
    #   a great many tokens can't make the dialog huge.
    # - The dialog's form DELETEs the group. The zone is rendered AFTER the
    #   group form, never inside it (forms don't nest); `Groups::Destroy`
    #   decides again.
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

      # Two sentences, each whole: what happens to the members, then to the
      # tokens.
      def effect = "#{t(".members", count: member_count)} #{t(".tokens", count: token_count)}"

      # One whole sentence per shape. A key is pluralised on one count, so the
      # sentence with both is nested: its outer level is the members' plural
      # category, its inner one the tokens', which `t` pluralises.
      def dialog_body
        return t(".dialog_body.no_members", count: token_count) if member_count.zero?
        return t(".dialog_body.members_only", count: member_count) if token_count.zero?

        t(".dialog_body.members_and_tokens.#{members_category}", count: token_count, members: member_count)
      end

      # The members' category is the I18n backend's own choice, made by asking
      # it to pluralise the outer level on the members' count and reading back
      # which branch it answered: whatever rule the backend applies to every
      # other `count` (Rails' one/other, or a locale's `i18n.plural.rule` under
      # `I18n::Backend::Pluralization`, with its `few` and `many`) applies here
      # too, and a language's file decides which branches it has.
      def members_category
        key = "admin.components.#{self.class.translation_scope}.dialog_body.members_and_tokens"
        I18n.t(key).key(I18n.t(key, count: member_count))
      end
    end
  end
end
