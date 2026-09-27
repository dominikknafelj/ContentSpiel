# The public site. Every request that isn't one of the named routes above the
# catch-all in config/routes.rb lands here with a locale and a path, and is
# answered by the matching `Page`, by a single `Post` rendered inside the page
# that lists it (the permalink fallback), a redirect to a record's current
# URL, or the theme 404 -- exactly the three outcomes `PublicSite::Resolver`
# can produce (spec §6.3). Preview (signed-in editors) is `PreviewController`
# (Task 7), which shares none of this: PublicController is deliberately
# cookie-less, so it can never carry a signed-in session.
class PagesController < PublicController
  # A request through the locale-prefixed route (config/routes.rb) whose
  # prefix names the site's *current* default locale has a second URL --
  # the unprefixed one -- that means exactly the same thing. Redirecting
  # keeps one canonical address per page rather than two competing ones.
  # SiteSetting#default_locale is a runtime setting, so this can't be
  # decided in the route itself the way the locale *constraint* is; it's
  # checked here, before rendering, so a link or sitemap entry built from an
  # old default takes effect on the very next request, not after a deploy.
  before_action :redirect_default_locale_prefix

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

  def show
    result = PublicSite::Resolver.new(scope: :published, urls: public_urls).call(locale: effective_locale, path: requested_path)

    case result.status
    when :found
      assign_record(result.record)
      # `stale?` answers a matching `If-None-Match` with a bare 304 itself --
      # `render :show` below only ever runs for a genuinely stale request.
      # `expires_in ... public: true` plus `stale?(public: true)` together
      # are what turn the response's `Cache-Control` into
      # `public, max-age=0, must-revalidate`: a CDN or browser may cache it,
      # but must always revalidate against the ETag rather than serving a
      # stale copy for up to `max-age` seconds.
      expires_in 0, public: true, must_revalidate: true
      render :show if stale?(etag: [ result.record, PublicSite.content_version ], public: true)
    when :redirect
      redirect_to result.location, status: result.http_status
    else
      render :not_found, status: :not_found
    end
  end

  private

  # A post renders inside its canonical listing page, as before.
  def assign_record(record)
    if record.is_a?(Post)
      @post = record
      @page = PublicSite::Paths.canonical_page(record)
      @post_list_block = @page.content_blocks.find { |block| block.lists?(record) }
    else
      @page = record
    end
  end

  def redirect_default_locale_prefix
    return unless public_urls.redundant_prefix?(params[:locale])

    path = "/#{params[:path]}".sub(%r{/+$}, "").presence || "/"
    path += "?#{request.query_string}" if request.query_string.present?
    redirect_to path, status: :found
  end

  def render_in_requested_locale(&block)
    I18n.with_locale(effective_locale, &block)
  end

  # The route param when the URL was explicitly prefixed (e.g. /de/about);
  # otherwise the site's current default -- the very locale
  # `redirect_default_locale_prefix` above would have sent an explicit-but-
  # redundant prefix away from, so by the time this is read, an absent
  # `params[:locale]` and the default locale mean the same thing.
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
