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

  helper_method :public_urls

  private

  # One `PublicSite::Urls` per request: every nav link, permalink and
  # hreflang alternate the response renders reads its host and preview state
  # off this same instance, and its per-record path memoization is only
  # worth having across the several links a single response renders, not
  # across requests.
  def public_urls
    @public_urls ||= PublicSite::Urls.new(host: request.base_url)
  end
end
