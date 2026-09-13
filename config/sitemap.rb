# frozen_string_literal: true

# The sitemap of the public site (page-tree design spec section 7). Generated
# by `rake sitemap:create` (or `sitemap:refresh`, which also pings the
# configured search engines) into public/, and evaluated by sitemap_generator
# inside its own interpreter -- so this file is a script, and its test
# (test/lib/sitemap_test.rb) runs it the same way the deploy does.

# Absolute URLs are required by the sitemap protocol, and nothing in a Rails
# app knows the canonical public host, so it is supplied by the environment.
# The default is the placeholder sitemap_generator's own installer writes: a
# sitemap generated without SITEMAP_HOST set is obviously wrong rather than
# quietly pointing at localhost.
SitemapGenerator::Sitemap.default_host = ENV.fetch("SITEMAP_HOST", "https://www.example.com")

# `include_root` would add "/" -- the one public URL that isn't a page: it only
# redirects to the default locale (config/routes.rb), and a sitemap is meant to
# list the destinations, not the redirect.
SitemapGenerator::Sitemap.create(include_root: false) do
  # Published only: a draft (or a page scheduled for a future date) has a
  # cached path the moment it is saved, but PagesController 404s it, so listing
  # it would point search engines at a URL that doesn't resolve.
  #
  # `find_each` rather than `all`, per the gem's README: the tree is walked in
  # batches instead of being loaded into memory at once.
  Page.published.find_each do |page|
    # Every locale the site is published in, off the same row: each locale
    # serves this page at its own path, and those are distinct URLs. The paths
    # are the cached ones `Page#full_path` reads, which is what the catch-all
    # route looks up, so what is listed here is exactly what resolves.
    #
    # The locale prefix is prepended rather than built with a route helper
    # because `page_path` would re-escape the slashes inside the path glob.
    # `full_path` is "/" for the root page, giving "/en/", and "/about" for a
    # child, giving "/en/about" -- both of which the route accepts.
    I18n.available_locales.each do |locale|
      add "/#{locale}#{page.full_path(locale)}", lastmod: page.updated_at
    end
  end
end
