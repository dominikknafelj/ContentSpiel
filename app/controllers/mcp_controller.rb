# The MCP server (design spec section 10): a fresh MCP::Server built per
# request (the "Rails (controller)" pattern from the mcp gem's own docs,
# https://ruby.sdk.modelcontextprotocol.io/server/transports/#rails-controller),
# not a single server mounted once at boot -- that pattern builds one fixed
# server_context for the app's whole lifetime, which can't carry the
# per-request bearer-token identity this endpoint authenticates.
#
# ActionController::API rather than ApplicationController: this is a bearer
# token API, not a browser session, and API controllers skip CSRF protection
# (ApplicationController's Authentication concern is cookie-session auth for
# human admins signing into CS Studio -- a different mechanism entirely).
class McpController < ActionController::API
  before_action :authenticate

  def create
    server = MCP::Server.new(
      name: "contentspiel",
      title: "ContentSpiel",
      version: "1.0.0",
      instructions: "Manage ContentSpiel's blog/resume/now-update posts across locales.",
      tools: [ Mcp::Tools::ListPosts, Mcp::Tools::GetPost, Mcp::Tools::CreatePost, Mcp::Tools::UpdatePost ],
      server_context: { user: @current_api_user }
    )

    # stateless: true -- there is no `Mcp-Session-Id` shared across requests
    # here, since a new server (and so a new session) is built every time;
    # serve_subscriptions_listen: false because `render` below buffers the
    # whole response body, which cannot serve the open SSE stream a
    # subscriptions/listen request would need. Neither tool here uses
    # subscriptions, so nothing is lost by declining it.
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      server,
      stateless: true,
      serve_subscriptions_listen: false
    )

    status, headers, body = transport.handle_request(request)
    render json: body.first, status: status, headers: headers
  end

  private

  def authenticate
    raw_token = request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]
    api_token = raw_token && ApiToken.authenticate(raw_token)

    return render(json: { error: "Unauthorized" }, status: :unauthorized) unless api_token

    api_token.record_usage!(request.remote_ip)
    @current_api_user = api_token.user

    # This controller is an `ActionController::API`, not an
    # `ApplicationController` (see the class comment), so it doesn't inherit
    # that controller's actor-setting `before_action` -- every write an MCP
    # tool makes through `Posts::Save` (etc.) is attributed to the bearer
    # token itself, not the human the token happens to belong to, since the
    # token -- not a session -- is what was actually authenticated here.
    Current.actor = api_token
    Current.channel = :mcp
  end
end
