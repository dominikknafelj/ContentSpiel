# Base for the public site (spec §6.4): no Authentication, no session, no
# CSRF token, no cookies -- the same response for everyone, so a browser or
# CDN may cache it. Preview (signed-in drafts) lives on /preview in its own
# controller for exactly this reason. Everything that varies per visitor
# (the theme toggle) stays in the browser.
class PublicController < ActionController::Base
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

  helper_method :public_urls

  private

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
end
