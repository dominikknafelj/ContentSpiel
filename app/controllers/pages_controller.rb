# The public site. Every request that isn't one of the named routes above the
# catch-all in config/routes.rb lands here with a locale and a path, and is
# answered by the matching `Page` -- or by a 404 if the tree has no page at
# that path.
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

    if @page.nil?
      render plain: "Not Found", status: :not_found
      return
    end

    render :show
  end

  private

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
