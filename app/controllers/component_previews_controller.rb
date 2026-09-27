# The controller ViewComponent previews render through: Lookbook (mounted at
# /lookbook, development only -- config/routes.rb) and the preview smoke test
# (test/components/previews_test.rb) both dispatch here, since Lookbook syncs
# `Lookbook.config.preview_controller` from `ViewComponent::Config.previews
# .controller` (see the lookbook gem's `Engine#opts`) rather than needing a
# controller of its own.
#
# A plain `ActionController::Base`, not `ApplicationController`: previews are
# dev/test-only (global constraints) and must never sit behind a signed-in
# session the way the rest of the admin does. It still needs `public_urls`,
# though -- every public component calls `page_url_path`/`post_url_path`
# (ThemeHelper/PagesHelper) via `ApplicationComponent`'s `helpers` delegation,
# and those read `public_urls` off whichever controller is rendering, the
# same way `PublicController`/`PreviewController` supply their own.
class ComponentPreviewsController < ActionController::Base
  include ViewComponent::PreviewActions

  helper_method :public_urls

  # Previews build their own sample data (`Page.create!`/`Post.create!`, the
  # pattern the global constraints already sanction for tests) rather than
  # unsaved records, because a component's `post_url_path`/`page_url_path`
  # link needs a real `public_paths` row to resolve -- an unsaved or
  # since-rolled-back post has none, and `link_to(name, nil)` raises
  # `ArgumentError` rather than quietly rendering a blank href (checked with
  # `bin/rails runner`). `requires_new: true` guarantees a real savepoint of
  # its own regardless of what's already open -- a bare transaction/rollback
  # would otherwise be a no-op nested inside the test suite's own per-test
  # transaction (or, in the other direction, roll that whole transaction back
  # instead of just this request's writes) -- so this rolls back exactly what
  # this one request wrote, and only that, once the response body is fully
  # rendered: a real editor clicking through Lookbook leaves the dev database
  # exactly as they found it.
  around_action :discard_preview_writes

  private

  def discard_preview_writes
    ActiveRecord::Base.transaction(requires_new: true) do
      yield
      raise ActiveRecord::Rollback
    end
  end

  def public_urls
    @public_urls ||= PublicSite::Urls.new(host: request.base_url)
  end
end
