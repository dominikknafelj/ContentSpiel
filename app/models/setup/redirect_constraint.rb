# Sends every request to /setup while setup is required (design spec
# 2026-09-26 §3). A route constraint rather than a before_action so it also
# covers the mounted Avo engine. Exempt: the wizard itself, CS Studio's
# sign-in, sign-out and password reset (an admin resuming setup -- cs-studio
# spec §3), the health check, the MCP endpoint (own bearer auth; no tokens
# exist yet anyway) and Active Storage (the logo preview while setup runs).
# The exemption check runs first so those paths never cost a database query.
#
# Deliberately narrower than the whole `/#{ContentSpiel::ADMIN_PATH}` scope:
# CS Studio's own root and every other admin screen still redirect to /setup
# while setup is pending, same as Avo does today -- only the three paths an
# admin needs to *resume* setup by signing back in are carved out.
module Setup
  module RedirectConstraint
    EXEMPT_PREFIXES = [
      "/setup",
      "/#{ContentSpiel::ADMIN_PATH}/sign-in",
      "/#{ContentSpiel::ADMIN_PATH}/sign-out",
      "/#{ContentSpiel::ADMIN_PATH}/password",
      "/up",
      "/mcp",
      "/rails/active_storage"
    ].freeze

    module_function

    def matches?(request)
      !exempt?(request.path) && Setup.required?
    end

    def exempt?(path)
      EXEMPT_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
    end
  end
end
