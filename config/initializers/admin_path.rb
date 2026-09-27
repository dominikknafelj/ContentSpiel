# Where CS Studio lives (cs-studio spec §3). Configurable because a
# well-known admin path is the first thing scanners try; read once at boot
# since routes are drawn from it. One URL-safe segment, or boot fails loudly.
module ContentSpiel
  ADMIN_PATH = ENV.fetch("ADMIN_PATH", "cs-studio").to_s.delete_prefix("/").delete_suffix("/").tap do |path|
    raise ArgumentError, "ADMIN_PATH must be one URL segment like \"cs-studio\" (got #{path.inspect})" unless path.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
  end
end
