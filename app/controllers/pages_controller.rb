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
  # The value is safe to pass through: the route's `locale` constraint admits
  # only the three locales the site is published in.
  around_action :render_in_requested_locale

  def show
    @page = Page.find_by_full_path(params[:locale], requested_path)
    return render :show if @page

    resolve_post_detail

    if @post
      render :show
    else
      render plain: "Not Found", status: :not_found
    end
  end

  private

  # No path matched a page. A `Post` has no page-tree node of its own (spec
  # section 4), so its permalink is the listing page's path plus its slug:
  # re-read the path as "a page, then a post slug" and see whether the page
  # that turns up actually lists posts, and one of them has that slug.
  #
  # `find_by_full_path` is what looks the parent up, exactly as above -- it
  # filters to published pages, so a draft listing page serves no permalinks
  # either, and its post detail URLs don't become a way to reach a page that
  # isn't public yet.
  def resolve_post_detail
    parent_path, _, candidate_slug = requested_path.rpartition("/")

    @page = Page.find_by_full_path(params[:locale], parent_path.presence || "/")

    # The page's first listing block in `position` order (the association is
    # ordered), which for every page the spec describes is its only one.
    @post_list_block = @page&.content_blocks&.find_by(block_type: :post_list)
    return if @post_list_block.nil?

    # Literally the same criteria the block's listing applies, so a page serves
    # detail views for exactly the posts it lists. (`limit` deliberately isn't
    # applied -- it trims how much of the list is shown, not which posts the
    # page is responsible for, which is why it lives in the partial rather than
    # in `listed_posts`.)
    @post = @post_list_block.listed_posts
      .find_by_localized_slug(params[:locale], candidate_slug)
  end

  def render_in_requested_locale(&block)
    I18n.with_locale(params[:locale], &block)
  end

  # The path as `Page#full_path` writes it: leading slash, no trailing one, and
  # "/" for the locale root (where the glob segment's default leaves `path`
  # empty).
  def requested_path
    path = "/#{params[:path]}".sub(%r{/+$}, "")
    path.presence || "/"
  end
end
