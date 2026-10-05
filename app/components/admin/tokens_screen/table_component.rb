module Admin
  module TokensScreen
    # The "Tokens" table of the AI assistant page: Name, Acts as (the user the
    # token authenticates as), Group, Created, Last used (the IP on a second
    # line, "Never" before the first request), Status (Active / Revoked) and
    # Revoke… behind a confirm dialog. A revoked token stays listed, dimmed,
    # with no action. No part of the token is shown: only its SHA-256 lookup digest
    # is stored, and nothing else of it exists to mask.
    #
    # `tokens` arrives already narrowed to what the viewer may see (their own,
    # or everyone's with `tokens.manage`) and ordered, with `user` and `group`
    # loaded.
    class TableComponent < Admin::AdminComponent
      def initialize(tokens:)
        @tokens = tokens
      end

      # Public: the confirm dialog's slot block runs in the *dialog's* context.
      def revoke_path(token)
        options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
        helpers.admin_api_token_path(token, **options)
      end

      private

      attr_reader :tokens

      def dialog_id(token) = "revoke-api-token-#{token.id}"

      def user_label(token) = Admin::UserNameComponent.new(user: token.user, user_id: token.user_id).label

      def revoke_body(token)
        "The assistant acting as #{user_label(token)} through this token loses access at once. " \
          "The token stays listed as revoked, and its past changes stay in the audit log."
      end

      def row_class(token) = token.revoked_at ? "border-b border-line align-top opacity-60" : "border-b border-line align-top"
    end
  end
end
