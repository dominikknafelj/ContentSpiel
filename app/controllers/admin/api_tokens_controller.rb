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
  #
  # Open to every signed-in user (access-control design spec §5 "AI
  # assistant tokens"): everyone sees and revokes their own tokens; only
  # `tokens.manage` sees -- and so can revoke -- everyone's, e.g. a
  # credential that's leaked. Another user's token is outside the list for
  # anyone else, so revoking it by id is a 404, not a 403.
  #
  # Each token is bounded by a group (design spec §3.3 "Tokens"): the form
  # offers only the groups the user may assign, defaulting to Read only,
  # and `ApiTokens::Issue` checks the submitted one again -- a forged
  # `group_id` for a group the user can't assign is refused with the 403
  # page.
  class ApiTokensController < BaseController
    def index
      load_screen
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
    # A failed issue never reaches the reveal: there's no raw token worth
    # showing, so the page comes back at 422 -- the same page, with the
    # service's own message under the field it is about (Name, or Group) and
    # the typed name kept. Nothing secret exists to keep out of the response.
    #
    # `name:` is always passed as a String (`params[:name].to_s`): to
    # `ApiTokens::Issue` a nil name means "pick Token N", and here the name is
    # required, so a missing or blank field must be the "Name can't be blank"
    # failure rather than a quiet default.
    def create
      group = AccessControl::Group.find_by(id: params[:group_id]) if params[:group_id].present?
      name = params[:name].to_s
      result = ApiTokens::Issue.call(Current.user, group: group, name: name)

      unless result.ok?
        forbidden_or(result) do
          load_screen
          @name = name
          # A refusal that named no group (or one that is gone) offers the
          # default again rather than an empty select.
          @selected_group_id = group&.id || default_group&.id
          messages = result.errors.presence || [ "The token couldn't be created" ]
          @name_errors, @group_errors = messages.partition { |message| message.start_with?("Name ") }
          render :index, status: :unprocessable_entity
        end
        return
      end

      load_screen
      @api_token, @raw_token = result.record

      response.set_header("Cache-Control", "no-store")
      render :create
    end

    # An already-revoked token (a stale tab's Revoke button, fix round 1,
    # m4) is answered with a notice and left alone -- revoking it again
    # would overwrite `revoked_at`, the list's record of *when* it stopped
    # working.
    def destroy
      api_token = visible_tokens.find(params[:id])

      if api_token.revoked_at
        redirect_to admin_api_tokens_path(**admin_url_options), status: :see_other, notice: "Token was already revoked"
        return
      end

      result = ApiTokens::Revoke.call(api_token)

      if result.ok?
        redirect_to admin_api_tokens_path(**admin_url_options), status: :see_other, notice: "Token revoked"
      else
        forbidden_or(result) { redirect_to admin_api_tokens_path(**admin_url_options), status: :see_other, alert: result.errors.to_sentence }
      end
    end

    private

    # What both `index` and the refused/successful `create` render: the
    # tokens the viewer may see (a just-issued one included, so the reveal
    # lists it) and the groups they may give a token.
    def load_screen
      @api_tokens = visible_tokens.includes(:user, :group).order(created_at: :desc, id: :desc)
      @assignable_groups = AccessControl.permitted_groups_for(Current.user)
      @selected_group_id = default_group&.id
      @name = ""
      @name_errors = []
      @group_errors = []
    end

    def visible_tokens
      can?("tokens.manage") ? ApiToken.all : ApiToken.where(user: Current.user)
    end

    # The form's preselected group (design spec §5: "defaulting to Read
    # only"), when the user may assign it.
    helper_method def default_group
      @assignable_groups.find { |group| group.name == AccessControl::Seeds::READ_ONLY_NAME }
    end

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
