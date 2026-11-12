# Where CS Studio lives (cs-studio spec §3). Configurable because a
# well-known admin path is the first thing scanners try; read once at boot
# since routes are drawn from it. One URL-safe segment, or boot fails loudly.
module ContentSpiel
  # First path segments the public site's own routing claims -- `ADMIN_PATH`
  # is drawn into `routes.rb` *before* the public catch-alls, so it would
  # otherwise silently win over any of these and swallow whichever one it
  # collided with, rather than boot failing loudly the way an unsafe segment
  # already does below. The backend's own segments (preview, setup, MCP, the
  # cable socket) are under the admin path and so collide with nothing; what
  # is left is every first segment a route outside it claims:
  #
  # - "up" -- Rails' own health check (`rails_health_check`);
  # - "rails" -- every engine Rails itself mounts under `/rails/*` in
  #   development (`/rails/info`, `/rails/mailers`, ActiveStorage's own
  #   `/rails/active_storage/...`);
  # - "lookbook" -- the component browser, development only;
  # - "assets" -- compiled asset URLs (`config.assets.prefix`'s own
  #   default);
  # - "sitemap.xml" -- `config/sitemap.rb`'s own output, served as a plain
  #   file under `public/`, never through the router at all -- listed
  #   anyway since a request for it still has to resolve to the sitemap, not
  #   to whatever `ADMIN_PATH` happened to be configured as;
  # - every code `SUPPORTED_LOCALES` could ever have enabled (not just
  #   `Locales.enabled` -- a runtime setting this boot-time check can't
  #   read, and a locale disabled today can be re-enabled tomorrow with no
  #   deploy, spec §4.4).
  RESERVED_PATHS = %w[up rails lookbook assets sitemap.xml].freeze + SUPPORTED_LOCALES.keys

  ADMIN_PATH = ENV.fetch("ADMIN_PATH", "cs-studio").to_s.delete_prefix("/").delete_suffix("/").tap do |path|
    raise ArgumentError, "ADMIN_PATH must be one URL segment like \"cs-studio\" (got #{path.inspect})" unless path.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
    raise ArgumentError, "ADMIN_PATH can't be #{path.inspect} -- that's already reserved" if RESERVED_PATHS.include?(path)
  end
end

# The address of Action Cable's socket, which `config/routes.rb` mounts under
# the admin path. turbo-rails' consumer reads it from `action_cable_meta_tag`
# (it asks `/cable` otherwise), and `live/connection.js` goes through that
# consumer. `ADMIN_PATH` stays read in this file alone.
Rails.application.config.action_cable.url = "/#{ContentSpiel::ADMIN_PATH}/cable"
