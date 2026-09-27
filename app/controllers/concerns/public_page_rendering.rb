# Shared by `PagesController` and `PreviewController` (spec §6.4): both
# resolve a `PublicSite::Resolver` result down to a rendered "pages/show" in
# the right locale, and the mechanics of doing that -- which locale a request
# is in, what a post-vs-page result assigns to the view, how the requested
# path is normalized -- don't differ between the two, even though the two
# controllers differ in everything else (session, caching, which resolver
# scope, which URL space their links stay in).
module PublicPageRendering
  extend ActiveSupport::Concern

  included do
    # The locale prefix is not only the key the path is looked up under: it is
    # the locale the page's translated content has to be *read* in, or /de/...
    # resolves a German path and then renders English text.
    #
    # Setting I18n.locale is enough on its own -- `Mobility.locale` reads back
    # `I18n.locale` whenever nothing has explicitly set a Mobility-specific one
    # (mobility 1.3's `Mobility.locale` is `read_locale || I18n.locale`), and
    # nothing in this request does. A second `Mobility.with_locale` wrapper would
    # be redundant.
    #
    # The value is safe to pass through: `effective_locale` is either the
    # route's own `locale` constraint (one of the three configured locales) or
    # the site's default locale, itself validated against that same list.
    around_action :render_in_requested_locale
  end

  private

  # A post renders inside its canonical listing page, as before. Returns
  # false -- and the caller renders the 404 -- for a post with no canonical
  # page right now: its current `public_paths` row can briefly outlive the
  # listing that gave it one (a block removed without callbacks, a sync not
  # yet run), and `:preview` finds that row without the `:published`
  # visibility check that would otherwise have turned it away first. There
  # is no page to render the post inside, so it's "not found" rather than a
  # NoMethodError on a nil page.
  def assign_record(record)
    if record.is_a?(Post)
      @page = PublicSite::Paths.canonical_page(record)
      return false if @page.nil?

      @post = record
      @post_list_block = @page.content_blocks.find { |block| block.lists?(record) }
    else
      @page = record
    end
    true
  end

  def render_in_requested_locale(&block)
    I18n.with_locale(effective_locale, &block)
  end

  # The route param when the URL was explicitly prefixed (e.g. /de/about, or
  # /preview/de/about); otherwise the site's current default. On the public
  # site, PagesController#redirect_default_locale_prefix sends an explicit
  # but redundant default-locale prefix away before this is ever read, so an
  # absent params[:locale] and the default locale always mean the same thing
  # there. PreviewController has no such redirect -- a preview link should
  # keep rendering at exactly the address a signed-in editor typed -- so both
  # spellings simply resolve to the same content there too, just without the
  # 302.
  def effective_locale
    params[:locale] || Locales.default
  end

  # The path as `Page#full_path` writes it: leading slash, no trailing one, and
  # "/" for the locale root (where the glob segment's default leaves `path`
  # empty).
  def requested_path
    path = "/#{params[:path]}".sub(%r{/+$}, "")
    path.presence || "/"
  end
end
