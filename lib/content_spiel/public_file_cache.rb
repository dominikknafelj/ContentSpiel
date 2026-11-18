# How long a cache may keep a file the site serves as it is: a year for a
# file whose name carries its digest, an hour for every other.
#
# A digested asset (`/assets/site-1a2b3c4d.css`, Propshaft's name) changes
# its address whenever its content changes, so a browser and a CDN may keep
# it for a year and never ask again (`immutable`). Every other file in
# `public/` keeps its address when its content changes: `/icon.svg`,
# `/icon.png`, `/icons/*`, `/robots.txt`, the sitemap, `/diagram-renderer.js`,
# the error pages, and the site's icons that `SiteIconsController` answers
# (`/favicon.ico`, `/apple-touch-icon.png`). Such a file is kept for an hour
# and may then be answered stale for a day while the cache asks again in the
# background: a change reaches every visitor within an hour and one more
# request, and the files are small enough that asking once an hour costs
# nothing. Production used to say a year for all of `public/` (Rails'
# default), and when 0.10.0 replaced CS Studio's icon a CDN and every
# browser that had seen the old one kept it.
#
# `ActionDispatch::Static` takes one header set for every file it serves, so
# it is given the short one (`.headers`, `config/environments/production.rb`
# and `test.rb`), and this middleware, before `ActionDispatch::Static` and
# `Propshaft::Server` (`config/application.rb`), gives the year back to a
# digested asset's answer. `SiteIconsController` says the short one with
# `expires_in`, from `KEPT_FOR` and `STALE_FOR`; `SHORT` is written in the
# order Rails writes those, so both answers carry the same header.
#
# In lib/ and required from config/application.rb, which inserts it while
# the application is configured, before autoloading is set up.
module ContentSpiel
  class PublicFileCache
    KEPT_FOR = 3600
    STALE_FOR = 86_400
    SHORT = "max-age=#{KEPT_FOR}, public, stale-while-revalidate=#{STALE_FOR}".freeze
    DIGESTED = "public, max-age=31536000, immutable".freeze

    # Propshaft's digest: a hyphen, 7 to 128 letters and digits, then the
    # extension (`Propshaft::Asset.extract_path_and_digest`).
    DIGEST = /-[0-9a-zA-Z]{7,128}\.[^\/]+\z/

    def self.headers = { "cache-control" => SHORT }

    def initialize(app, prefix:)
      @app = app
      @prefix = "#{prefix.chomp("/")}/"
    end

    def call(env)
      status, headers, body = @app.call(env)
      headers["cache-control"] = DIGESTED if served?(status) && digested?(Rack::Request.new(env).path_info.to_s)
      [ status, headers, body ]
    end

    private

    def served?(status) = (200..299).cover?(status) || status == 304

    def digested?(path) = path.start_with?(@prefix) && DIGEST.match?(path.delete_prefix(@prefix))
  end
end
