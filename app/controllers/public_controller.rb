# Base for the public site (spec §6.4): no Authentication, no session, no
# CSRF token, no cookies -- the same response for everyone, so a browser or
# CDN may cache it. Preview (signed-in drafts) lives on /preview in its own
# controller for exactly this reason. Everything that varies per visitor
# (the theme toggle) stays in the browser.
class PublicController < ActionController::Base
  # NO COOKIE LEAVES, AS A WALL. First in the file, so it is around every
  # callback and action of this class and of its subclasses, one that
  # answers early included (`leave_no_cookie` below says what it does and
  # what it does not hold).
  around_action :leave_no_cookie

  # Rails' automatic "fall back to layouts/application" convention only
  # fires because ApplicationController's own name happens to match that
  # file (its `controller_path` is literally "application"). Skipping
  # ApplicationController -- the whole point of this class -- skips that
  # coincidence too, so the public theme layout has to be named explicitly
  # or every response here renders with no layout at all.
  layout "application"

  allow_browser versions: :modern
  stale_when_importmap_changes

  # Same reason as before the split: an Accept header naming another format
  # would otherwise reach a missing template and a 500.
  before_action { request.format = :html }

  # The public site's own channel (final fix wave, Minor 9). Nothing here
  # calls a service or asks access control today, but a nil actor on a nil
  # channel is the *trusted* console case (`AccessControl::Checker`), so a
  # future public code path that did would silently act with every right.
  # `:public` is untrusted: a nil actor on it is denied everything.
  before_action { Current.channel = :public }

  # NO SESSION AND NO TOKEN, AS A WALL TOO (theming spec §2: "no CSRF token
  # on a public page, which is the same cookie-less answer for every
  # visitor").
  # The first line of this file was a convention while every public
  # template was the CMS's own. A theme's templates are not: a `form_with`
  # or a `button_to` in a theme's footer, `csrf_meta_tags` in its head or a
  # `form_authenticity_token` anywhere asks Rails for the token, Rails reads
  # the session to mint it, and the response, which says
  # `Cache-Control: public`, leaves with a `Set-Cookie`. So:
  #
  # - the session of a public request is never committed (`:skip`, which
  #   the session middleware asks before it writes the cookie), whatever a
  #   template read or wrote in it;
  # - `protect_against_forgery?` answers false, which is what
  #   `csrf_meta_tags` and every form helper ask before they print a token;
  # - `form_authenticity_token`, which mints one without asking, answers nil.
  #
  # Nothing public needs either: every public route is a GET
  # (`config/routes.rb`: `pages#show` only) and no action reads the session.
  # A theme's GET form (a search box) works as before, and a form that posts
  # to another service posts without a token of this application, which that
  # service could not have checked anyway. `PreviewController` is not a
  # `PublicController` and keeps both: it is signed in, private and never
  # cached. `Theme::Check` refuses the same words in a theme's template with
  # a message that says why; this is what holds for a spelling it does not
  # see (`test/integration/theme_pages_test.rb`: "a public page drawn under
  # a theme sets no cookie and carries no token…").
  before_action { request.session_options[:skip] = true }

  helper_method :public_urls

  private

  # THE COOKIE JAR IS NOT THE SESSION. `cookies[:seen] = "1"` in a theme's
  # template (a consent banner, an A/B flag: honest mistakes), and
  # `cookies.signed`, `.encrypted`, `.permanent` and `cookies.delete`, are
  # kept in the request's jar and written into the response by
  # `ActionDispatch::Cookies`, a middleware of its own that never asks the
  # session's `:skip`. The response says `Cache-Control: public`, so a
  # shared cache that keeps it would hand one visitor's `Set-Cookie` to the
  # next. So, once the action and its templates are done (the layout is
  # rendered inside the action), and also when a callback answered early:
  #
  # - the request gets a NEW jar, built from the cookies the browser sent
  #   and holding no write and no delete, which is the one the middleware
  #   then finds and writes nothing from (actionpack 8.1.4,
  #   `ActionDispatch::Cookies#call`: `request.cookie_jar.write(response)`).
  #   Nothing is sent to delete a cookie either: a signed-in editor's
  #   cookies are neither changed nor taken away by reading a public page;
  # - a `Set-Cookie` put on the response by hand (`response.set_cookie`,
  #   `response.headers["Set-Cookie"] = …`) is taken off.
  #
  # A write to the flash is a write to the session and goes with it
  # (`:skip`, below).
  #
  # WHAT THIS HOLDS: no `Set-Cookie` leaves a response of this controller
  # or of a subclass, whatever a template calls in the view. What it does
  # not: an action that raises is answered by the exceptions application,
  # outside this controller (the cookie middleware writes nothing then: it
  # is passed by the exception), and a cookie set by a script in the browser
  # (`document.cookie`) is the browser's and never this response's.
  # `Theme::Check` refuses a cookie write in a theme's template at the boot
  # with a sentence that says why; this is what holds for the spelling it
  # does not see (`test/integration/theme_pages_test.rb`: "a public page
  # drawn under a theme sets no cookie and carries no token…", "a signed-in
  # editor reads a public page under a grasping theme and is still signed
  # in…").
  def leave_no_cookie
    yield
  ensure
    request.cookie_jar = ActionDispatch::Cookies::CookieJar.build(request, request.cookies) if request.have_cookie_jar?
    response.delete_header("Set-Cookie")
  end

  def protect_against_forgery? = false

  def form_authenticity_token(**) = nil

  # One `PublicSite::Urls` per request: every nav link, permalink and
  # hreflang alternate the response renders reads its host and preview state
  # off this same instance, and its per-record path memoization is only
  # worth having across the several links a single response renders, not
  # across requests.
  #
  # THE HOST IS THE SITE'S, NOT THE REQUEST'S (safe-address spec, "Head
  # tags"). `request.base_url` is whatever `Host` -- or, behind a proxy,
  # `X-Forwarded-Host` -- the client sent, and the absolute addresses built
  # from this instance are printed into the page: `og:url`, the `hreflang`
  # alternates, the `canonical` link. This response is the same for every
  # visitor and publicly cacheable, so one request under a made-up host
  # would otherwise leave that host in the head for whoever is served the
  # cached copy, and tell a search engine the page lives there. The
  # configured address (`PUBLIC_HOST`) is used whenever there is one; the
  # request's origin is only the fallback of a checkout with none, the same
  # one CS Studio's "Copy address" takes. `PreviewController` keeps the
  # request's origin on purpose: a preview is private, never cached, and its
  # addresses are where the editor is.
  # `test/integration/public_head_address_test.rb`;
  # `test/lib/public_address_guard_test.rb` keeps the views from reading the
  # request's host themselves.
  def public_urls
    @public_urls ||= PublicSite::Urls.new(host: PublicSite::Urls.configured_host || request.base_url)
  end

  # What a public ETag adds for the addresses the head prints (`og:url`, the
  # canonical link, the hreflang alternates), splatted into the ETag's keys:
  # nothing when a site address is configured, since they are then the same
  # under every host and a configured site's ETags stay what they were; the
  # origin `public_urls` fell back to when none is. Without it a client or a
  # shared cache that revalidates, under a second name the same checkout
  # answers to, with an ETag it was given under the first would be told 304
  # and keep a body whose head names the first.
  # `test/integration/public_head_address_test.rb`.
  def origin_etag_key
    PublicSite::Urls.configured_host ? [] : [ public_urls.host ]
  end
end
