# Base for every public-theme ViewComponent (open-types spec §5). Components
# read no controller instance variables (global constraints) -- everything
# they need arrives as an explicit keyword input -- but the handful of
# ThemeHelper/PagesHelper methods every block/post component reaches for
# (`translated`, `rich_text`, `post_date`, `resume_period`, `post_url_path`,
# `page_url_path`, and `render_block` for a section drawing the blocks in
# it) still have to come from *somewhere*, and that somewhere
# is `helpers`, not a plain `include`.
#
# `helpers` proxies to the view context of whichever controller is actually
# rendering: `PagesController` on the public site, `PreviewController` under
# /preview, `ComponentPreviewsController` for Lookbook and component tests.
# `post_url_path`/`page_url_path` read through each controller's own
# `public_urls` (PagesHelper), which differs between them -- PreviewController
# builds its with `preview: true` so every link a previewed page renders
# stays under /preview. Delegating to `helpers` rather than including
# ThemeHelper/PagesHelper directly is what keeps that distinction working: an
# `include` would call the *module's* `public_urls`, and there isn't one --
# it's a controller method the module only ever expected to be mixed into.
class ApplicationComponent < ViewComponent::Base
  delegate :translated, :rich_text, :post_date, :resume_period, :post_url_path, :page_url_path, :render_block, to: :helpers
end
