require "test_helper"

# "Connect an AI assistant" (design spec §6.1): the token list, a one-time
# reveal of a freshly issued token, and revoke. The raw token exists only
# in the `create` response itself -- never in a redirect, the flash, the
# session, the database or the log.
class Admin::ApiTokensTest < ActionDispatch::IntegrationTest
  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  # Checked directly here since CS Studio's own Admin::BaseController gate
  # is worth a test per screen, the same as Admin::MindGraphTest and
  # Admin::SystemStatusTest already do.
  test "an unauthenticated request is redirected to sign-in" do
    get "/cs-studio/api_tokens"
    assert_redirected_to "/cs-studio/sign-in"
  end

  # CS Studio has no standalone show page (the list is the whole screen), so
  # a token's owner is asserted against its own list row.
  test "the list shows active and revoked tokens with who each acts as (the display name: the email while there is no name), last used and IP" do
    sign_in_as(users(:one))
    active, = ApiToken.generate!(users(:one), name: "claude-desktop")
    active.record_usage!("203.0.113.5")
    revoked, = ApiToken.generate!(users(:two), name: "old-agent")
    revoked.revoke!

    get "/cs-studio/api_tokens"

    assert_response :success
    assert_select "#" + ActionView::RecordIdentifier.dom_id(active) do
      assert_select "*", text: /claude-desktop/
      assert_select "*", text: /#{Regexp.escape(users(:one).display_name)}/
      assert_select "*", text: /203\.0\.113\.5/
      assert_select "*", text: /Active/
      assert_select "*", text: /Admin/ # the token's group
      assert_select "button", text: "Revoke…"
    end
    assert_select "#" + ActionView::RecordIdentifier.dom_id(revoked) do
      assert_select "*", text: /old-agent/
      assert_select "*", text: /#{Regexp.escape(users(:two).display_name)}/
      assert_select "*", text: /Revoked/
      assert_select "button", text: "Revoke…", count: 0
      assert_select "[class~='opacity-60']" # dimmed, still listed
    end
    assert_not_includes response.body, active.token_digest
  end

  test "the page is a numbered flow: create a token, add it to your assistant, the tokens table" do
    sign_in_as(users(:one))
    ApiToken.generate!(users(:one), name: "claude-desktop")
    get "/cs-studio/api_tokens"

    assert_select "h1", text: "Connect an AI assistant"
    assert_select "h2", text: "1 · Create a token"
    assert_select "h2", text: "2 · Add it to your assistant"
    assert_select "h2", text: "Tokens"
    assert_select "input[name=name][required][placeholder='claude-desktop']"
    assert_select "select[name=group_id] option[data-description]"
    assert_select "button", text: "Create token"
    assert_select "button", text: "Copy", minimum: 2 # the URL and the configuration
    headers = css_select("table th").map { |header| header.text.strip }
    assert_equal %w[Name Acts\ as Group Created Last\ used Status], headers.first(6)
    assert_no_match(/masked|••••/, response.body)
  end

  # Fix round 1: the create form is a plain POST, so the reveal arrives as
  # a whole document (see admin/api_tokens/create for why).
  test "the create form opts out of Turbo" do
    sign_in_as(users(:one))
    get "/cs-studio/api_tokens"
    assert_select "form[action='/cs-studio/api_tokens'][data-turbo='false']"
    assert_select "head meta[name='turbo-cache-control']", count: 0
  end

  test "the list names the MCP URL and a client config snippet" do
    sign_in_as(users(:one))
    get "/cs-studio/api_tokens"

    assert_includes response.body, "#{PublicSite::Urls.default_host}/mcp"
    assert_select "pre", text: /mcpServers/
  end

  test "creating a token reveals it once, no-store, in the response itself" do
    sign_in_as(users(:one))
    assert_difference -> { ApiToken.count }, 1 do
      post "/cs-studio/api_tokens", params: { name: "claude-desktop", group_id: access_control_groups(:read_only).id }
    end

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    # Its own document, opted out of Turbo's snapshot cache (fix round 1).
    assert_select "head meta[name='turbo-cache-control'][content='no-cache']"
    raw = raw_token_from(response.body)
    token = ApiToken.order(:id).last
    assert_equal users(:one), token.user
    assert_equal access_control_groups(:read_only), token.group
    assert_equal "claude-desktop", token.name
    assert token.authenticate_token(raw)
    assert_select "[role=status]", text: /Copy this token now\. It won't be shown again\./
    assert_select "button", text: "Copy token"
    assert_select "pre", text: /#{raw}/ # the client config snippet carries it
    assert_select "pre#api-token-config", text: /Bearer #{raw}/
    assert_select "table", text: /claude-desktop/
    assert_includes response.body, "#{PublicSite::Urls.default_host}/mcp"

    assert_nil flash[:notice]
    assert_not_includes session.to_hash.to_s, raw
    assert_not_includes flash.to_hash.to_s, raw

    get "/cs-studio/api_tokens"
    assert_not_includes response.body, raw
  end

  test "the raw token never reaches the log" do
    sign_in_as(users(:one))
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    ActionController::Base.logger = Rails.logger

    post "/cs-studio/api_tokens", params: { name: "logged", group_id: access_control_groups(:read_only).id }
    raw = raw_token_from(response.body)

    assert_not_includes io.string, raw
    assert_includes io.string, "api_tokens" # the logger really was capturing this request
  ensure
    Rails.logger = original
    ActionController::Base.logger = original
  end

  test "revoking a token stops it authenticating MCP requests immediately" do
    sign_in_as(users(:one))
    token, raw = ApiToken.generate!(users(:one))

    mcp_list(raw)
    assert_response :success

    delete "/cs-studio/api_tokens/#{token.id}"
    assert_redirected_to "/cs-studio/api_tokens"
    assert token.reload.revoked_at.present?

    mcp_list(raw)
    assert_response :unauthorized
  end

  test "the modules column links to the AI assistant module" do
    sign_in_as(users(:one))
    get "/cs-studio/api_tokens"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/api_tokens']", text: "AI assistant"
  end

  private

  def raw_token_from(body)
    Nokogiri::HTML::Document.parse(body).at_css("#api-token-value").text.strip
  end

  # The MCP transport only accepts a loopback Host (`McpTest`'s own setup
  # explains why), while the admin session cookie belongs to the default
  # test host -- so each MCP call switches host and switches straight back.
  def mcp_list(raw)
    admin_host = host
    host! "127.0.0.1"
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
        "Authorization" => "Bearer #{raw}" }
  ensure
    host! admin_host
  end

  # A failed issue never renders the reveal: no token exists, so the page
  # comes back at 422 with the service's own message under the field it is
  # about and the typed name kept (it used to redirect with a flash).
  test "a blank name re-renders the page at 422 with the error under Name and no token" do
    sign_in_as(users(:one))

    assert_no_difference [ -> { ApiToken.count }, -> { Audit::Event.count } ] do
      post "/cs-studio/api_tokens", params: { name: "   ", group_id: access_control_groups(:read_only).id }
    end

    assert_response :unprocessable_entity
    assert_select "#token-name-error", text: /Name can't be blank/
    assert_select "#api-token-value", count: 0
    assert_select "[role=status]", text: /Copy this token now/, count: 0
    assert_select "select[name=group_id] option[selected][value=?]", access_control_groups(:read_only).id.to_s
  end

  test "a missing name field is the blank-name error too" do
    sign_in_as(users(:one))

    assert_no_difference -> { ApiToken.count } do
      post "/cs-studio/api_tokens", params: { group_id: access_control_groups(:read_only).id }
    end

    assert_response :unprocessable_entity
    assert_select "#token-name-error", text: /Name can't be blank/
  end

  test "a duplicate active name is refused at 422 with the typed name kept" do
    sign_in_as(users(:one))
    ApiToken.generate!(users(:one), name: "claude-desktop")

    assert_no_difference -> { ApiToken.count } do
      post "/cs-studio/api_tokens", params: { name: "Claude-Desktop", group_id: access_control_groups(:read_only).id }
    end

    assert_response :unprocessable_entity
    assert_select "#token-name-error", text: /already the name of one of this user's active tokens/
    assert_select "input[name=name][value='Claude-Desktop']"
    assert_select "#api-token-value", count: 0
  end

  test "the reveal never survives a reload of the list" do
    sign_in_as(users(:one))
    post "/cs-studio/api_tokens", params: { name: "once", group_id: access_control_groups(:read_only).id }
    raw = raw_token_from(response.body)

    get "/cs-studio/api_tokens"
    assert_not_includes response.body, raw
    assert_select "#api-token-value", count: 0
    assert_select "table", text: /once/
  end

  test "the revoke dialog names the token and the user" do
    sign_in_as(users(:one))
    token, = ApiToken.generate!(users(:one), name: "claude-desktop")

    get "/cs-studio/api_tokens"

    dialog = "dialog#revoke-api-token-#{token.id}"
    assert_select dialog, text: /Revoke “claude-desktop”\?/
    assert_select dialog, text: /The assistant acting as #{Regexp.escape(users(:one).display_name)} through this token loses access at once\. The token stays listed as revoked, and its past changes stay in the audit log\./
    assert_select "#{dialog} button", text: "Revoke token"
  end

  # Fix round 1 (m4): a stale tab's Revoke keeps the original revoked_at.
  test "revoking an already-revoked token keeps its revoked_at and says so" do
    sign_in_as(users(:one))
    token, = ApiToken.generate!(users(:one))
    token.update!(revoked_at: 2.days.ago.change(usec: 0))
    revoked_at = token.revoked_at

    delete "/cs-studio/api_tokens/#{token.id}"

    assert_redirected_to "/cs-studio/api_tokens"
    assert_equal revoked_at, token.reload.revoked_at
    follow_redirect!
    assert_select "[role=status]", text: "Token was already revoked"
  end

  # --- Token groups (access-control design spec §3.3 "Tokens", §5) -------------

  test "an author may choose only Read only or Author, defaulting to Read only" do
    # The fixture group is empty (so trivially assignable); a real branch
    # editors group edits pages, which an author can't.
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.edit", scope: {})
    sign_in_as(users(:author))
    get "/cs-studio/api_tokens"

    options = css_select("select[name=group_id] option").map { |option| option.text.strip }
    assert_equal [ "Author", "Read only" ], options
    assert_select "select[name=group_id] option[selected]", text: "Read only"
  end

  test "an author forging group_id = Admin is refused" do
    sign_in_as(users(:author))

    assert_no_difference -> { ApiToken.count } do
      post "/cs-studio/api_tokens", params: { name: "forged", group_id: access_control_groups(:admin).id }
    end

    assert_response :forbidden
    assert_select "main", text: /You don't have permission to give a token that group/
  end

  # Final fix wave (S-M6): every signed-in user reaches this endpoint, and the
  # id is theirs to choose -- the refusal must not hand back the group's name.
  test "a refused group id doesn't disclose the group's name" do
    secret = AccessControl::Group.create!(name: "Project Nightjar")
    AccessControl::Grant.create!(group: secret, permission: "users.manage", scope: {})
    sign_in_as(users(:author))

    post "/cs-studio/api_tokens", params: { name: "probe", group_id: secret.id }

    assert_response :forbidden
    assert_not response.body.include?("Nightjar"), "the refusal names the group"
  end

  test "a missing group is an error under Group, not a token" do
    sign_in_as(users(:author))

    assert_no_difference -> { ApiToken.count } do
      post "/cs-studio/api_tokens", params: { name: "no-group" }
    end

    assert_response :unprocessable_entity
    # Under Group and nowhere else: its own slot, tied to the select -- not "any alert on the page".
    assert_select "#token-group-error", text: "Choose a group for the token", count: 1
    assert_select "select#group_id[aria-describedby~='token-group-error']"
    assert_select "#token-name-error", count: 0
  end

  test "users see only their own tokens unless they have tokens.manage" do
    mine, = ApiToken.generate!(users(:author), group: access_control_groups(:read_only))
    theirs, = ApiToken.generate!(users(:reader), group: access_control_groups(:read_only))

    sign_in_as(users(:author))
    get "/cs-studio/api_tokens"
    assert_select "#" + ActionView::RecordIdentifier.dom_id(mine)
    assert_select "#" + ActionView::RecordIdentifier.dom_id(theirs), count: 0

    sign_in_as(users(:two))
    get "/cs-studio/api_tokens"
    assert_select "#" + ActionView::RecordIdentifier.dom_id(theirs)
  end
end
