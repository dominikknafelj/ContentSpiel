# Rate limits the MCP endpoint (/mcp) per bearer token, not per IP -- it's a
# token-authenticated API (design spec section 10), and multiple legitimate
# agents could share an IP (office network, VPN, hosted runner), so an IP
# bucket would either punish innocent tokens together or (if wide enough to
# avoid that) fail to bound a single misbehaving one. Requests with no
# token, or one that doesn't parse out of the Authorization header, share a
# per-IP bucket instead -- otherwise omitting the header (or spraying
# garbage tokens to brute-force one) would dodge rate limiting entirely
# rather than just failing authentication in McpController#authenticate.
#
# A dedicated in-memory store, not Rails.cache: test's cache_store is
# :null_store (every write is a no-op, which would make this throttle
# silently do nothing under test), and rate-limit counters don't belong
# mixed into the app's general-purpose cache regardless. This app runs a
# single Puma worker by default (config/puma.rb) so an in-process store
# sees every request; if WEB_CONCURRENCY is ever raised above 0, switch
# this to Rails.cache (already solid_cache-backed in production) so counts
# are shared across worker processes instead of one bucket per worker.
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

# Referenced by McpRateLimitTest so the limit is defined once. Not on
# McpController itself: this early in boot (config/initializers run before
# the autoloader can resolve app/ constants) referencing McpController here
# raises NameError.
Rack::Attack::MCP_RATE_LIMIT = 60
Rack::Attack::MCP_RATE_LIMIT_PERIOD = 1.minute

Rack::Attack.throttle("mcp/requests", limit: Rack::Attack::MCP_RATE_LIMIT, period: Rack::Attack::MCP_RATE_LIMIT_PERIOD) do |req|
  next unless req.path == "/mcp" && req.post?

  raw_token = req.get_header("HTTP_AUTHORIZATION").to_s[/\ABearer\s+(.+)\z/i, 1]
  raw_token.present? ? "token:#{Digest::SHA256.hexdigest(raw_token)}" : "ip:#{req.ip}"
end

Rack::Attack.throttled_responder = lambda do |req|
  match_data = req.env["rack.attack.match_data"]
  retry_after = match_data[:period] - (match_data[:epoch_time] % match_data[:period])

  [
    429,
    { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
    [ { error: "Too many requests" }.to_json ]
  ]
end
