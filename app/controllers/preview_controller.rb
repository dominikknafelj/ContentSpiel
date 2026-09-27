# Drafts and scheduled content at their would-be URLs, for signed-in editors
# only (spec §6.4). Renders the public theme's own views so the preview is
# faithful, but never cacheable or indexable, and every link it renders stays
# under /preview.
class PreviewController < ApplicationController
  include PublicPageRendering

  # Same reason as PublicController's own before_action: an Accept header
  # naming another format would otherwise reach a missing template and a 500.
  before_action { request.format = :html }

  helper_method :public_urls

  def show
    result = PublicSite::Resolver.new(scope: :preview, urls: public_urls).call(locale: effective_locale, path: requested_path)
    response.set_header("Cache-Control", "private, no-store")
    response.set_header("X-Robots-Tag", "noindex")

    case result.status
    when :found
      assign_record(result.record)
      @preview_record = @post || @page
      render "pages/show"
    when :redirect
      redirect_to result.location, status: :found
    else
      render "pages/not_found", status: :not_found
    end
  end

  private

  # One `PublicSite::Urls` per request, `preview: true` so every link this
  # response renders (nav, listing, hreflang alternates) stays under
  # /preview rather than the public address the same record would resolve
  # to outside preview.
  def public_urls
    @public_urls ||= PublicSite::Urls.new(preview: true, host: request.base_url)
  end
end
