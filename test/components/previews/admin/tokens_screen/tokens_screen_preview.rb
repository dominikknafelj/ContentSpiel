module Admin
  module TokensScreen
    # The AI assistant page's three sections: step 1 empty, as refused (422),
    # and as the one-time reveal; step 2 with its placeholder; the table.
    class TokensScreenPreview < ViewComponent::Preview
      def create_step
        render Admin::TokensScreen::CreateStepComponent.new(groups: AccessControl::Group.order(:id).to_a, form_url: "#")
      end

      def create_step_refused
        render Admin::TokensScreen::CreateStepComponent.new(
          groups: AccessControl::Group.order(:id).to_a, form_url: "#", name: "claude-desktop",
          name_errors: [ "Name is already the name of one of this user's active tokens" ]
        )
      end

      def create_step_reveal
        render Admin::TokensScreen::CreateStepComponent.new(groups: AccessControl::Group.order(:id).to_a, form_url: "#", raw_token: "0" * 64)
      end

      def connect_step
        render Admin::TokensScreen::ConnectStepComponent.new(mcp_url: "https://example.com/mcp", config: "{\n  \"mcpServers\": {}\n}")
      end

      def table
        render Admin::TokensScreen::TableComponent.new(tokens: ApiToken.includes(:user, :group).order(created_at: :desc).limit(5))
      end
    end
  end
end
