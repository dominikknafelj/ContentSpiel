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

  # Same wrapping as `Admin::BaseController#use_site_time_zone` (dashboard
  # spec §5): an MCP client reads/writes `published_at` as ISO 8601
  # (`Mcp::PostSerializer`/`Time.zone.parse`-backed tools), and that offset
  # should match CS Studio's own rather than always being UTC.
  around_action :use_site_time_zone

  def create
    server = MCP::Server.new(
      name: "contentspiel",
      title: "ContentSpiel",
      version: "1.0.0",
      instructions: instructions,
      tools: [ Mcp::Tools::ListPosts, Mcp::Tools::GetPost, Mcp::Tools::CreatePost, Mcp::Tools::UpdatePost,
        Mcp::Tools::ListMedia, Mcp::Tools::GetMedia ],
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

  # Access-control design spec §3.4: the server tells the client whose
  # rights it acts with -- the token's own user and group, so an agent
  # can explain a refusal ("You don't have permission to …") instead of
  # retrying. Only this token's own facts: never another user, token or
  # group, and not the group's grants (an agent learns what it may do by
  # doing it; the list tools already show only what it may read).
  def instructions
    "Manage ContentSpiel's blog/resume/now-update posts across locales, and browse its media library " \
      "for images to reference from a post/page's rich text (::image{asset=\"ID\" alt=\"…\"}). " \
      "This token acts as #{@api_token.user.email_address} limited to the #{@api_token.group.name} group: " \
      "it can only see and change what both that user and that group are allowed to. " \
      "A post outside that scope is reported as not found; a change it isn't allowed to make " \
      "is refused with a \"You don't have permission to …\" error."
  end

  def use_site_time_zone(&block)
    Time.use_zone(Current.site.time_zone, &block)
  end

  def authenticate
    raw_token = request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]
    api_token = raw_token && ApiToken.authenticate(raw_token)

    return render(json: { error: "Unauthorized" }, status: :unauthorized) unless api_token

    api_token.record_usage!(request.remote_ip)
    @api_token = api_token
    @current_api_user = api_token.user

    # This controller is an `ActionController::API`, not an
    # `ApplicationController` (see the class comment), so it doesn't inherit
    # that controller's actor-setting `before_action` -- every write an MCP
    # tool makes through `Posts::Save` (etc.) is attributed to the bearer
    # token itself, not the human the token happens to belong to, since the
    # token -- not a session -- is what was actually authenticated here.
    Current.actor = api_token
    Current.channel = :mcp
    Current.request_id = request.request_id
    Current.ip_address = request.remote_ip
  end
end
