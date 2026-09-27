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

# `include_root` would add "/" unconditionally -- the loop below already adds
# it itself (as the root Page's own entry in the current default locale, which
# is exactly the page "/" resolves to), so leaving this on would list it twice.
SitemapGenerator::Sitemap.create(include_root: false) do
  # Read once rather than inside the loop below: Current.site memoizes within
  # a process, but nothing here needs to touch it more than once anyway.
  default_locale = Current.site.default_locale

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
    # `full_path` is "/" for the root page and "/about" for a child. The
    # site's current default locale gets no prefix at all (config/routes.rb,
    # PagesHelper#locale_prefix) -- every other configured locale keeps one,
    # e.g. "/de/about".
    I18n.available_locales.each do |locale|
      prefix = locale.to_s == default_locale ? "" : "/#{locale}"
      add "#{prefix}#{page.full_path(locale)}", lastmod: page.updated_at
    end
  end
end
