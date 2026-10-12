# frozen_string_literal: true

# The sitemap of the public site (page-tree design spec section 7). Generated
# by `rake sitemap:create` (or `sitemap:refresh`, which also pings the
# configured search engines) into public/, and evaluated by sitemap_generator
# inside its own interpreter -- so this file is a script, and its test
# (test/lib/sitemap_test.rb) runs it the same way the deploy does.

# Absolute URLs are required by the sitemap protocol, and nothing in a Rails
# app knows the canonical public host, so it is supplied by the environment:
# `PUBLIC_HOST`, the site's address (`SiteAddress`, docs/reference/hosting.md),
# or `SITEMAP_HOST`, its older name, read when the first is not set.
# The default is the placeholder sitemap_generator's own installer writes: a
# sitemap generated with neither set is obviously wrong rather than
# quietly pointing at localhost. `PublicSite::Urls.default_host` is the same
# fallback chain `Urls#url_for` uses everywhere else, so a URL built here and
# one built for, say, an MCP response never disagree about the host.
SitemapGenerator::Sitemap.default_host = PublicSite::Urls.default_host

# One `Urls` instance for the whole run: its per-record path memoization
# means a record with rows in several locales (every published record) only
# computes its `alternates` once rather than once per locale entry below.
urls = PublicSite::Urls.new(host: SitemapGenerator::Sitemap.default_host)

# A record's own visibility, plus every ancestor page's: the same
# `:published` rule `PagesController` resolves requests against (spec §6.3),
# not merely a `public_paths` row existing (that row is written the moment
# a draft is saved, spec §5.4). A page published under an unpublished parent
# must not appear here either, so the sitemap never advertises a URL the
# resolver would 404.
visible = PublicSite::Resolver.method(:visible?)

# When what a visitor sees of a record last changed: the time its current copy
# came into force, or the time it went live if that was later (a record
# scheduled ahead). An autosave of a live record does not move it. A record
# with no copy is dated by its row, as before. Read once, without the copies'
# content.
came_into_force = Publishing::Version.in_force.group(:record_type, :record_id).maximum(:live_at)

# `include_root` would add "/" unconditionally -- the loop below already adds
# it itself (as the root Page's own entry in the current default locale, which
# is exactly the page "/" resolves to), so leaving this on would list it twice.
SitemapGenerator::Sitemap.create(include_root: false) do
  # One entry per current `public_paths` row (page or post, every enabled
  # locale) rather than walking the page tree and re-deriving posts' paths by
  # hand -- `public_paths` already *is* the current, canonical address of
  # every record in every language (spec §5.1), so this lists exactly what
  # `PagesController` would resolve each one back to.
  #
  # `find_each` rather than `all`, per the gem's README: the table is walked
  # in batches instead of being loaded into memory at once. `includes(:record)`
  # avoids an N+1 for the polymorphic `record` lookup below.
  PublicPath.current.includes(:record).find_each do |public_path|
    record = public_path.record # public: rows (an address and whether it is visible are the rows'; the date comes from the copy)
    next unless visible.call(record)

    path = urls.path_for(record, public_path.locale)
    next if path.nil?

    # `alternates` from the same `urls` instance: each locale's entry lists
    # every language's URL, including its own, exactly as
    # `application.html.erb`'s hreflang tags do for a live request.
    alternates = urls.alternates(record).map { |locale, href| { href: href, lang: locale } }
    key = [ public_path.record_type, public_path.record_id ]
    lastmod = came_into_force.key?(key) ? [ came_into_force[key], record.published_at ].compact.max : record.updated_at
    add path, lastmod: lastmod, alternates: alternates
  end
end
