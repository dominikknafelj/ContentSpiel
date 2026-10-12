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
  #
  # WHICH LISTING THE POST STANDS IN FOR, on a page with more than one that
  # lists it: the first in READING ORDER (`BlockOutline#reading_order`: the
  # top level by position, each section followed by its blocks column by
  # column). Not the first by `position`, which is what the association's
  # own order gives: a position is counted per container, so a listing at
  # position 5 of a column in the page's first section is read before a
  # top-level listing at position 1, and a top-level listing and one in a
  # column can share a position, where the database may return either
  # first -- the detail then moved between two places from one request to
  # the next.
  #
  # The outline built for that is THE PAGE'S ONE for this render: it is
  # handed to the view in `@block_outlines`, the very variable
  # `ThemeHelper#block_outline` memoises in, so the view draws from this
  # outline and builds no second one (an outline sorts and groups every
  # block of the page). A controller's instance variables are copied to its
  # view; the helper is not called from here, because a controller does not
  # run view helpers, and the variable is the hand-over both sides name.
  #
  # Loads no more than deciding that takes: the page's blocks, in the one
  # query the render would make for them anyway (it used to be a query for
  # the listing blocks alone here, and the render's own for all of them
  # afterwards). The images a rendered page reads are `preload_page_images`,
  # which each controller calls once it knows it will render
  # (`PagesController` only after `stale?`, so a 304 never pays for them).
  # `as_published` is the including controller's: the public site answers the
  # record rebuilt from its published copy (`Publishing.published`), the
  # preview the record itself. The address was resolved from the ROW either
  # way: slug, tree and publish state are not in a copy.
  def assign_record(record)
    if record.is_a?(Post)
      page = PublicSite::Paths.canonical_page(record)
      return false if page.nil?

      @page = as_published(page)
      @post = as_published(record)
      outline = BlockOutline.new(@page.content_blocks)
      @block_outlines = { @page => outline }
      @post_list_block = outline.reading_order.find { |block| block.lists?(record) }
    else
      @page = as_published(record)
    end
    true
  end

  # A page's rendered body (`pages/show.html.erb`) reads its hero and every
  # image block's own `media_asset` -- one association access each, per
  # block, that `Blocks::ImageComponent`/the hero render would otherwise
  # send to the database one at a time (Task 4 review: a page with N image
  # blocks cost N queries just to find each block's asset, before
  # `Media::PictureComponent` even asks that asset for its `srcset`).
  # `ActiveRecord::Associations::Preloader`, not `.includes(...)` on a fresh
  # query, because `page` here is already the exact record `PublicSite
  # ::Resolver` resolved (and, for a post permalink, the one `PublicSite
  # ::Paths.canonical_page` found) -- re-querying it with `.includes` would
  # just be a second, redundant fetch of the same row. `Media::Asset
  # ::VARIANT_INCLUDES` nested under each association is what lets
  # `Media::PictureComponent#srcset_attribute` (`Media::Asset#srcset`) read
  # each asset's processed-variant digests without a further query per
  # image, the same reasoning `Media::Asset.with_variants` documents for a
  # plain asset listing.
  # Two calls, not one nested: a page rebuilt from a copy has its blocks set
  # as a loaded association, and the blocks themselves are what the second
  # call is handed, so it never depends on how a preloader treats a target
  # that was set by hand.
  def preload_page_images(page)
    ActiveRecord::Associations::Preloader.new(records: [ page ], associations: { hero_media_asset: Media::Asset::VARIANT_INCLUDES }).call
    ActiveRecord::Associations::Preloader.new(records: page.content_blocks.to_a, associations: { media_asset: Media::Asset::VARIANT_INCLUDES }).call
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
