module Admin
  module TokensScreen
    # Step 2 of the AI assistant page, "Add it to your assistant": the MCP URL
    # and a ready-to-paste `mcpServers` client configuration, each with its own
    # Copy (`admin--tokens--reveal#copy`, which reads the element named by
    # `source`). On the list the configuration carries a placeholder; on the
    # one-time reveal (`raw_token:`) the real token is filled in and the block
    # is a `secret` target, blanked on `pagehide` together with the token itself.
    class ConnectStepComponent < Admin::AdminComponent
      def initialize(mcp_url:, config:, raw_token: nil)
        @mcp_url = mcp_url
        @config = config
        @raw_token = raw_token
      end

      private

      attr_reader :mcp_url, :config

      def secret? = @raw_token.present?

      def config_data = secret? ? { "admin--tokens--reveal-target": "secret" } : {}

      def copy_data(source) = { action: "admin--tokens--reveal#copy", "admin--tokens--reveal-source-param": source }
    end
  end
end
