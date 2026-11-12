# Sends every request to /setup while setup is required (design spec
# 2026-09-26 §3). A route constraint rather than a before_action so it also
# covers CS Studio itself. Exempt: the wizard itself, CS Studio's sign-in,
# sign-out and password reset (an admin resuming setup -- cs-studio spec §3),
# the health check, the MCP endpoint (own bearer auth; no tokens exist yet
# anyway) and Active Storage (the logo preview while setup runs). The
# exemption check runs first so those paths never cost a database query.
#
# ONLY A PAGE LOAD IS SENT INTO THE WIZARD (`#page_load?`): a GET or HEAD
# that asks for HTML by name, is no prefetch (Turbo's `X-Sec-Purpose`, the
# browser's `Sec-Purpose`) and, where the browser says, is meant for a
# document or a script's fetch (`Sec-Fetch-Dest`). Everything else -- a
# write, an icon the browser asks for on its own, DevTools' file, a
# prefetch -- is answered 404 by `.refuses?`'s route, a bare Rack answer that
# loads no session. Sent into the wizard, such a request loaded the session
# and the cookie store wrote it back as it read it, over whatever a
# parallel request had just kept there.
#
# Deliberately narrower than the whole `/#{ContentSpiel::ADMIN_PATH}` scope:
# CS Studio's own root and every other admin screen still redirect to /setup
# while setup is pending -- only the three paths an admin needs to *resume*
# setup by signing back in are carved out.
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
    PREFETCH_HEADERS = %w[X-Sec-Purpose Sec-Purpose].freeze
    PAGE_DESTINATIONS = %w[document empty].freeze

    module_function

    # A page load while setup is pending: redirected to /setup.
    def matches?(request)
      !exempt?(request.path) && page_load?(request) && Setup.required?
    end

    # Any other request while setup is pending: answered 404.
    def refuses?(request)
      !exempt?(request.path) && !page_load?(request) && Setup.required?
    end

    def page_load?(request)
      return false unless request.get? || request.head?
      return false if PREFETCH_HEADERS.any? { |name| request.headers[name].to_s.include?("prefetch") }

      destination = request.headers["Sec-Fetch-Dest"]
      return false if destination.present? && !PAGE_DESTINATIONS.include?(destination)

      request.headers["Accept"].to_s.include?("text/html")
    end

    def exempt?(path)
      EXEMPT_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
    end
  end
end
