# The public site. Every request that isn't one of the named routes above the
# catch-all in config/routes.rb lands here with a locale and a path, and is
# answered by the matching `Page` -- or by a 404 if the tree has no page at
# that path.
class PagesController < ApplicationController
  # ApplicationController includes Authentication, whose `before_action`
  # requires a session on every controller by default. The public site is the
  # one place that has to be readable without signing in.
  allow_unauthenticated_access

  def show
    @page = Page.find_by_full_path(params[:locale], requested_path)

    if @page.nil?
      render plain: "Not Found", status: :not_found
      return
    end

    render :show
  end

  private

  # The path as `Page#full_path` writes it: leading slash, no trailing one, and
  # "/" for the locale root (where the glob segment's default leaves `path`
  # empty).
  def requested_path
    path = "/#{params[:path]}".sub(%r{/+$}, "")
    path.presence || "/"
  end
end
