# The public site. Every request that isn't one of the named routes above the
# catch-all in config/routes.rb lands here with a locale and a path, and is
# answered by the matching `Page`, by a single `Post` rendered inside the page
# that lists it (the permalink fallback below), or by a 404 when the path is
# neither.
class PagesController < ApplicationController
  # ApplicationController includes Authentication, whose `before_action`
  # requires a session on every controller by default. The public site is the
  # one place that has to be readable without signing in.
  allow_unauthenticated_access

  # The route's `format: false` only stops a URL segment like ".json" from
  # being read as a format -- a request naming one through its `Accept` header
  # instead reaches `render :show` exactly as before, negotiates against that
  # header, finds no `show.json.erb`, and raises `ActionView::MissingTemplate`.
  # That class isn't in Rails' own `rescue_responses` table, so it would reach
  # the requester as a raw 500 rather than a 404. Pinning the format here closes
  # both the URL-segment and the header route to the same failure.
  before_action { request.format = :html }

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
  # SiteSetting#default_locale, itself validated against that same list.
  around_action :render_in_requested_locale

  def show
    @page = Page.find_by_public_path(effective_locale, requested_path, include_unpublished: preview_allowed?)
    if @page
      mark_preview
      return render :show
    end

    resolve_post_detail

    if @post
      mark_preview
      render :show
    else
      render plain: "Not Found", status: :not_found
    end
  end

  private

  # Signed-in editors see unpublished pages and posts at their real URL
  # (spec §10.4); everyone else keeps getting 404 from the published scopes.
  def preview_allowed?
    return @preview_allowed if defined?(@preview_allowed)

    @preview_allowed = authenticated?.present?
  end

  # A preview must never be cached: it shows content visitors can't see.
  def mark_preview
    @preview_status = [ (@post || @page).status, @page.status ].find { |status| status != "live" }
    response.set_header("Cache-Control", "no-store") if @preview_status
  end

  # No path matched a page. A `Post` has no page-tree node of its own (spec
  # section 4), so its permalink is the listing page's path plus its slug:
  # re-read the path as "a page, then a post slug" and see whether the page
  # that turns up actually lists posts, and one of them has that slug.
  #
  # `find_by_public_path` is what looks the parent up, exactly as above -- it
  # filters to published pages, so a draft listing page serves no permalinks
  # either, and its post detail URLs don't become a way to reach a page that
  # isn't public yet.
  def resolve_post_detail
    parent_path, _, candidate_slug = requested_path.rpartition("/")

    @page = Page.find_by_public_path(effective_locale, parent_path.presence || "/", include_unpublished: preview_allowed?)

    # The page's first listing block in `position` order (the association is
    # ordered), which for every page the spec describes is its only one.
    @post_list_block = @page&.content_blocks&.find_by(block_type: :post_list)
    return if @post_list_block.nil?

    # Literally the same criteria the block's listing applies, so a page serves
    # detail views for exactly the posts it lists. (`limit` deliberately isn't
    # applied -- it trims how much of the list is shown, not which posts the
    # page is responsible for, which is why it lives in the partial rather than
    # in `listed_posts`.)
    @post = @post_list_block.listed_posts(include_unpublished: preview_allowed?)
      .find_by_localized_slug(effective_locale, candidate_slug)
  end

  def redirect_default_locale_prefix
    return unless params[:locale].present? && params[:locale] == Current.site.default_locale

    path = "/#{params[:path]}".sub(%r{/+$}, "").presence || "/"
    path += "?#{request.query_string}" if request.query_string.present?
    redirect_to path, status: :found
  end

  def render_in_requested_locale(&block)
    I18n.with_locale(effective_locale, &block)
  end

  # The route param when the URL was explicitly prefixed (e.g. /de/about);
  # otherwise the site's current default (SiteSetting#default_locale) --
  # the very locale `redirect_default_locale_prefix` above would have sent an
  # explicit-but-redundant prefix away from, so by the time this is read, an
  # absent `params[:locale]` and the default locale mean the same thing.
  def effective_locale
    params[:locale] || Current.site.default_locale
  end

  # The path as `Page#full_path` writes it: leading slash, no trailing one, and
  # "/" for the locale root (where the glob segment's default leaves `path`
  # empty).
  def requested_path
    path = "/#{params[:path]}".sub(%r{/+$}, "")
    path.presence || "/"
  end
end
