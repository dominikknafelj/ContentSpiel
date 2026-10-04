require "test_helper"

# Rate limiting for the MCP endpoint (config/initializers/rack_attack.rb):
# per-token, not per-IP, since /mcp is a bearer-token API where many agents
# could legitimately share an IP. See that initializer's comment for why.
class McpRateLimitTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @user = User.create!(email_address: "agent@example.com", password: "password12345")
    @token, @raw_token = ApiToken.generate!(@user)
    host! "127.0.0.1"
  end

  def mcp_post(raw_token)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
      headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
        "Authorization" => "Bearer #{raw_token}" }
  end

  # Frozen time: Rack::Attack's counter buckets requests into fixed windows
  # aligned to the wall clock (here, per calendar minute), so 60-odd real
  # HTTP round-trips straddling a minute boundary would split across two
  # buckets and never trip the throttle -- flaky by wall-clock luck, not a
  # real assertion failure. Freezing time keeps every request in one bucket.
  test "a token exceeding the per-minute request limit gets a 429 with Retry-After" do
    travel_to Time.current do
      Rack::Attack::MCP_RATE_LIMIT.times { mcp_post(@raw_token) }
      assert_response :success

      mcp_post(@raw_token)

      assert_response :too_many_requests
      assert_equal "Too many requests", response.parsed_body["error"]
      assert response.headers["Retry-After"].present?
    end
  end

  test "a different token has its own, unaffected limit" do
    other_user = User.create!(email_address: "agent2@example.com", password: "password12345")
    _other_token, other_raw = ApiToken.generate!(other_user)

    travel_to Time.current do
      Rack::Attack::MCP_RATE_LIMIT.times { mcp_post(@raw_token) }
      mcp_post(other_raw)

      assert_response :success
    end
  end
end
