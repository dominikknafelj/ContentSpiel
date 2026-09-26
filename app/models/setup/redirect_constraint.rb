# Sends every request to /setup while setup is required (design spec
# 2026-09-26 §3). A route constraint rather than a before_action so it also
# covers the mounted Avo engine. Exempt: the wizard itself, sign-in and
# password reset (an admin resuming setup), the health check, the MCP
# endpoint (own bearer auth; no tokens exist yet anyway) and Active Storage
# (the logo preview while setup runs). The exemption check runs first so
# those paths never cost a database query.
module Setup
  module RedirectConstraint
    EXEMPT_PREFIXES = %w[/setup /session /passwords /up /mcp /rails/active_storage].freeze

    module_function

    def matches?(request)
      !exempt?(request.path) && Setup.required?
    end

    def exempt?(path)
      EXEMPT_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
    end
  end
end
