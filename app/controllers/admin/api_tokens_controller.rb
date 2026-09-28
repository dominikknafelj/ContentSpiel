module Admin
  # "Connect an AI assistant" (design spec §6.1, Task 9): every MCP bearer
  # token, active and revoked, with when/where it was last used; "Create
  # token" (`ApiTokens::Issue`, the only place a raw token is ever minted);
  # and Revoke (`ApiTokens::Revoke`, immediate -- `ApiToken.authenticate`
  # only ever considers `active` rows).
  #
  # Tokens belong to whoever creates them (`Current.user`): an MCP client
  # holding one inherits that user's authoring identity (`ApiToken`'s own
  # comment), so nobody mints a token that authenticates as someone else.
  # The list shows every user's tokens, though, so any admin can revoke a
  # credential that's leaked, whoever it belongs to.
  class ApiTokensController < BaseController
    def index
      @api_tokens = ApiToken.includes(:user).order(created_at: :desc)
    end

    # The one-time reveal. *Rendered*, never redirected, the same rule the
    # setup wizard's own MCP-token step follows (`SetupController#update_
    # mcp_token`): a redirect would need the raw token to survive into a
    # second request, i.e. to sit in the flash or the session (both a
    # cookie), and it must never be stored anywhere -- `ApiToken` keeps only
    # its bcrypt digest. Nothing logs it either: it's generated here, not
    # submitted (so it's in no request parameter for `filter_parameters` to
    # even have to catch), and Rails never logs a response body.
    #
    # `no-store` keeps the response out of every HTTP cache, the browser's
    # back/forward cache included. The Turbo side of "never shown again":
    # the create form is a plain (non-Turbo) POST, so the reveal is its own
    # document whose head carries `turbo-cache-control: no-cache` -- Turbo
    # never snapshots it, and Back from it refetches the list -- and
    # `admin--token-reveal` blanks the token on `pagehide`. Reloading the
    # reveal itself can only re-POST (the browser asks first), which mints
    # a *new* token; it never shows this one again.
    #
    # A failed issue (fix round 1, m1) never reaches the reveal: there's no
    # raw token worth showing, so it's an ordinary redirect back to the list
    # with the service's own errors -- nothing secret to keep out of the flash.
    def create
      result = ApiTokens::Issue.call(Current.user)

      unless result.ok?
        redirect_to admin_api_tokens_path(**admin_url_options), status: :see_other,
          alert: result.errors.to_sentence.presence || "The token couldn't be created"
        return
      end

      @api_token, @raw_token = result.record

      response.set_header("Cache-Control", "no-store")
      render :create
    end

    # An already-revoked token (a stale tab's Revoke button, fix round 1,
    # m4) is answered with a notice and left alone -- revoking it again
    # would overwrite `revoked_at`, the list's record of *when* it stopped
    # working.
    def destroy
      api_token = ApiToken.find(params[:id])

      if api_token.revoked_at
        redirect_to admin_api_tokens_path(**admin_url_options), status: :see_other, notice: "Token was already revoked"
        return
      end

      result = ApiTokens::Revoke.call(api_token)

      if result.ok?
        redirect_to admin_api_tokens_path(**admin_url_options), status: :see_other, notice: "Token revoked"
      else
        redirect_to admin_api_tokens_path(**admin_url_options), status: :see_other, alert: result.errors.to_sentence
      end
    end

    private

    # The endpoint an assistant connects to: the public host (the same
    # `PublicSite::Urls.default_host` every absolute public URL is built
    # from) plus `/mcp` (`McpController`, outside the admin scope).
    helper_method def mcp_url = "#{PublicSite::Urls.default_host}/mcp"

    # A ready-to-paste client configuration, in the `mcpServers` shape
    # MCP clients (Claude Desktop/Code, Cursor, ...) share -- `token` is the
    # raw token on the reveal and a placeholder on the list.
    helper_method def mcp_client_config(token)
      JSON.pretty_generate(
        "mcpServers" => {
          "contentspiel" => {
            "type" => "http",
            "url" => mcp_url,
            "headers" => { "Authorization" => "Bearer #{token}" }
          }
        }
      )
    end
  end
end
