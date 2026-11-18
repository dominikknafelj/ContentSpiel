# The icons a browser asks for by a fixed address, whatever a page links:
# `/favicon.ico` (every browser, before or without a page), and
# `/apple-touch-icon.png` with `/apple-touch-icon-precomposed.png` (iOS and
# iPadOS ask both by default when a page is added to the home screen or
# shown in a list). Without these routes each went through the public router
# and drew the site's 404 page.
#
# THE THEME'S FILE, ELSE THE CMS'S: a theme that brings `favicon.ico` or
# `apple-touch-icon.png` (a 180x180 PNG) in its assets/images answers with
# it (`Theme#site_icon`), and otherwise the CMS's own, in public/icons/ (a
# file at public/favicon.ico would be served by `ActionDispatch::Static`
# before any route, and a theme could never replace it). The icons a page
# links are the theme's `_icons` partial's own (the default links
# `/icon.svg`, `/icon.png` and `/apple-touch-icon.png`).
#
# On the public wall's terms (`Cookieless`): an `ActionController::API`
# carries no session, so the answer sets no cookie. Its address never
# changes when the icon does, so a cache keeps it for the hour every
# undigested file in public/ is kept for (`ContentSpiel::PublicFileCache`),
# never longer.
class SiteIconsController < ActionController::API
  DEFAULTS = Rails.root.join("public/icons")

  def favicon = send_icon("favicon.ico", "image/x-icon")

  def touch = send_icon("apple-touch-icon.png", "image/png")

  private

  def send_icon(name, type)
    expires_in ContentSpiel::PublicFileCache::KEPT_FOR, public: true, stale_while_revalidate: ContentSpiel::PublicFileCache::STALE_FOR
    send_file(Theme.current.site_icon(name) || DEFAULTS.join(name), type: type, disposition: "inline")
  end
end
