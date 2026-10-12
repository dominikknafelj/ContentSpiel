# The public site. Every request that isn't one of the named routes above the
# catch-all in config/routes.rb lands here with a locale and a path, and is
# answered by the matching `Page`, by a single `Post` rendered inside the page
# that lists it (the permalink fallback), a redirect to a record's current
# URL, or the theme 404 -- exactly the three outcomes `PublicSite::Resolver`
# can produce (spec §6.3). Preview (signed-in editors) is `PreviewController`
# (Task 7), which shares none of this: PublicController is deliberately
# cookie-less, so it can never carry a signed-in session.
class PagesController < PublicController
  include PublicPageRendering

  # A request through the locale-prefixed route (config/routes.rb) whose
  # prefix names the site's *current* default locale has a second URL --
  # the unprefixed one -- that means exactly the same thing. Redirecting
  # keeps one canonical address per page rather than two competing ones.
  # SiteSetting#default_locale is a runtime setting, so this can't be
  # decided in the route itself the way the locale *constraint* is; it's
  # checked here, before rendering, so a link or sitemap entry built from an
  # old default takes effect on the very next request, not after a deploy.
  before_action :redirect_default_locale_prefix

  # The content version is read before anything it stands for: ahead of the
  # resolver, the record and the settings row. A write that commits while
  # this request runs is then seen as new content under the old version -- a
  # render cached under a key the bump is about to retire, harmless -- and
  # never as old content under the new version, which would stay cached
  # until some later published change.
  #
  # Prepended, so it runs before every other callback here. The settings row
  # can still have been loaded earlier: the locale-prefixed route's
  # constraint (`LocaleRouteConstraint`) asks which languages are enabled
  # before any controller code runs -- for every URL with a first segment,
  # since the router tries that route first and only the constraint says
  # that "about" in `/about` is no language. That copy is dropped, so the
  # row this response is rendered from is read after the version too: one
  # more query on every URL but `/`, the one address the prefixed route
  # can't match and so the one where nothing has loaded the row yet.
  prepend_before_action :read_content_version_first

  def show
    result = PublicSite::Resolver.new(scope: :published, urls: public_urls).call(locale: effective_locale, path: requested_path)

    case result.status
    when :found
      # A POST is read and rebuilt first: whether it is shown at all depends on
      # its listing page's blocks (`assign_record` returns false for none).
      # A PAGE is not: its ETag names its copy by id (one light statement,
      # `etag_key_of`) and the copy is read and rebuilt, blocks included, only
      # for a response that is rendered, so a 304 costs that statement and
      # not the page's weight.
      light = result.record.is_a?(Page) # public: rows (the resolver's record is only asked its class here)
      return render(:not_found, status: :not_found) unless light || assign_record(result.record) # public: rows (assign_record reads the copy through as_published)

      # `stale?` answers a matching `If-None-Match` with a bare 304 itself --
      # `render :show` below only ever runs for a genuinely stale request.
      # `expires_in ... public: true` plus `stale?(public: true)` together
      # are what turn the response's `Cache-Control` into
      # `public, max-age=0, must-revalidate`: a CDN or browser may cache it,
      # but must always revalidate against the ETag rather than serving a
      # stale copy for up to `max-age` seconds.
      #
      # The ETag is everything the response is built from that Rails' own
      # template digest (of `pages/show` alone) doesn't cover:
      # - the resolved record and the site's content version (`PublicSite`,
      #   three queries, already read by `read_content_version_first`);
      # - the settings row, which every page prints (title, tagline, footer),
      #   so the ETag is right even in the instant between a settings commit
      #   and its bump;
      # - `RichText.code_revision`, the deployed revision: the version moves
      #   only with published content, so without it a deploy that changed a
      #   component, the layout or the stylesheet's digest would keep being
      #   answered 304 until somebody published something;
      # - the year, which the footer prints: a 304 on 1 January would
      #   otherwise confirm last year's copyright line;
      # - with no site address configured, the request's origin
      #   (`origin_etag_key`): the head's addresses then follow the host the
      #   request named, and nothing else here does.
      #
      # What the ETag says of the record is its copy's id (`etag_key_of`): the
      # copy never changes once taken, so the id names its content, and a
      # change that comes into force by the clock is a different id AND a
      # different content version (the newest `live_at` in force). The images
      # and their variants are loaded only past `stale?`, for a response that
      # is actually rendered.
      expires_in 0, public: true, must_revalidate: true
      keys = light ? [ etag_key_of(result.record) ] : [ @page, @post ].map { |record| etag_key_of(record) } # public: rows (the ETag names the copy's id, not content)
      if stale?(etag: [ *keys, PublicSite.current_content_version, Current.site, RichText.code_revision, Time.current.year, *origin_etag_key ], public: true)
        assign_record(result.record) if light # public: rows (assign_record reads the copy through as_published)
        preload_page_images(@page)
        render :show
      end
    when :redirect
      redirect_to result.location, status: result.http_status
    else
      render :not_found, status: :not_found
    end
  end

  private

  def as_published(record) = Publishing.published(record)

  # By the page's copy and the post's (`Publishing::Listing`).
  def lists_post?(block, post) = Publishing::Listing.lists?(block, post)

  # What of a record the ETag depends on: its copy's id, or, for a record
  # served from its rows (a draft or one with no copy), the row. The rows'
  # `updated_at` moves with every autosave, which the public does not see.
  # A record already rebuilt from its copy names it; a row is asked once,
  # without the copy's content (the id and the time only).
  def etag_key_of(record)
    version = record.published_version
    if version.nil? && record.published_at.present?
      version = Publishing::Version.current_for([ record ], columns: %w[id record_type record_id live_at])[[ record.class.polymorphic_name, record.id ]]
    end
    version ? [ record.class.name, record.id, version.id ] : record
  end

  def read_content_version_first
    PublicSite.current_content_version
    Current.site = nil
  end

  def redirect_default_locale_prefix
    return unless public_urls.redundant_prefix?(params[:locale])

    path = "/#{params[:path]}".sub(%r{/+$}, "").presence || "/"
    path += "?#{request.query_string}" if request.query_string.present?
    redirect_to path, status: :found
  end
end
