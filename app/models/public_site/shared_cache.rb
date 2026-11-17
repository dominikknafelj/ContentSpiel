# How long a shared cache in front of the site (a CDN, Varnish, nginx) may
# keep a published public page, from one variable,
# PUBLIC_SHARED_CACHE_SECONDS: a whole number of seconds, 0 or more.
#
# Unset, blank or 0, a public page says what it always said,
# `max-age=0, public, must-revalidate`: anyone may store it, nobody may answer
# from it without asking again (a cheap 304 against the ETag). Above 0
# (`PagesController#show`, the `:found` answer that is rendered or confirmed
# with a 304, and no other):
#
#   Cache-Control: public, max-age=0, s-maxage=N, stale-while-revalidate=86400
#
# A browser still asks again on every visit (`max-age=0`, then the ETag); a
# SHARED cache may answer from its copy for N seconds (`s-maxage`, which only
# a shared cache reads) and, after that, once more from the stale copy while
# it fetches a new one in the background, for up to a day
# (`stale-while-revalidate`). So a published change reaches a visitor within
# N seconds, plus whatever the cache itself adds (a CDN's own minimum TTL, a
# request that refreshes the copy only after it was served). No
# `must-revalidate`: it would forbid the stale answer `stale-while-revalidate`
# allows.
#
# WHY IT IS SAFE TO SHARE: a public page is the same answer for every
# visitor. The public wall (`Cookieless`) commits no session and takes every
# `Set-Cookie` off, whatever a theme's template does, and no public page
# reads who is asking; what it does read of the request (its origin, with no
# PUBLIC_HOST) is in the ETag and in the URL a cache keys on. A search's
# answer is the visitor's own and stays `private, no-store`
# (`PublicPageRendering#answer_search_privately`), a 404 or a redirect never
# takes this header, and the preview and CS Studio are other controllers.
#
# Read when the application starts (`config/initializers/public_shared_cache.rb`):
# a value that is not a whole number of 0 or more stops the boot, in every
# environment, with a message that names the variable (a misspelt value must
# not quietly mean "never cache" or "cache for a day").
module PublicSite
  module SharedCache
    class Invalid < StandardError; end

    # A day: long enough to bridge a quiet night on a small site, short
    # enough that a cache never answers from a copy older than that.
    STALE_WHILE_REVALIDATE = 86_400

    # The seconds the variable names; 0 when it is unset or blank. Digits
    # only, so `60s`, `-1`, `1.5` and `1e3` are refused, not read as a number.
    def self.parse(value)
      text = value.to_s.strip
      return 0 if text.empty?
      raise Invalid, "PUBLIC_SHARED_CACHE_SECONDS must be a whole number of seconds, 0 or more (such as 60), or unset." unless text.match?(/\A\d+\z/)

      Integer(text, 10)
    end

    def self.read(env = ENV) = parse(env["PUBLIC_SHARED_CACHE_SECONDS"])

    # The value of this process, read once.
    def self.seconds = @seconds ||= read

    def self.on? = seconds.positive?

    # Called from the initializer, so a bad value stops the boot.
    def self.check! = seconds

    # For a test: the seconds for a block, then the process's own again.
    def self.with(value)
      before = @seconds
      @seconds = value
      yield
    ensure
      @seconds = before
    end
  end
end
