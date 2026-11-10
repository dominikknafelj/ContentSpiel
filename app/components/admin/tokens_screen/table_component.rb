module Admin
  module TokensScreen
    # The "Tokens" table of the AI assistant page: Name, Acts as (the user the
    # token authenticates as), Group, Created, Last used (the IP on a second
    # line, "Never" before the first request), Status and Revoke… behind a
    # confirm dialog. No part of the token is shown: only its SHA-256 lookup
    # digest is stored, and nothing else of it exists to mask.
    #
    # A token's state is a system's state (`Admin::Ui::StateChipComponent`),
    # never a publication's: Active is ok, Revoked is off with the time it
    # was revoked as the chip's detail. A revoked token stays listed with no
    # action, its words `meta`, never dimmed by opacity (which would take the
    # chip and the time below their contrast).
    #
    # The table scrolls sideways inside its card (`.admin-table-scroll--x`)
    # with its Name column sticky. That holds only while no row is one link:
    # a sticky cell is the containing block of `.admin-row-link`'s cover,
    # which would then cover the name cell alone.
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

      def user_label(token) = Admin::Ui::UserNameComponent.new(user: token.user, user_id: token.user_id).label

      def words_class(token) = token.revoked_at ? "text-meta" : "text-ink"

      def state_chip(token)
        return Admin::Ui::StateChipComponent.new(tone: :ok, label: t(".active")) unless token.revoked_at

        Admin::Ui::StateChipComponent.new(tone: :off, label: t(".revoked"), detail: render(Admin::Ui::TimeAgoComponent.new(time: token.revoked_at)))
      end
    end
  end
end
