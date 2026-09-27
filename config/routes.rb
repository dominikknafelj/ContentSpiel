Rails.application.routes.draw do
  # While setup is required, every route below is unreachable (design spec
  # 2026-09-26 §3): these two catch-alls are declared first, so they win over
  # Avo and the public page routes. A lambda, so the constant is only
  # resolved per request (never while routes load during boot).
  constraints(->(request) { Setup::RedirectConstraint.matches?(request) }) do
    match "/", to: redirect("/setup", status: 302), via: :all, as: :setup_required_root
    match "*path", to: redirect("/setup", status: 302), via: :all, format: false, as: :setup_required
  end

  mount_avo do
    get "pages_tree", to: "tools#pages_tree", as: :pages_tree
    # PATCH rather than the tool's own GET verb -- this is what the tree's
    # Stimulus controller calls on every drop, inside `mount_avo` so it
    # inherits the same session gate as the page itself. The moved page's id
    # travels in the body alongside `parent_id`/`position` rather than the
    # path, so the view can hand the controller one fixed URL up front
    # instead of building one per node.
    patch "pages_tree/reorder", to: "tools#reorder_page", as: :reorder_page

    # What the Trix editor's paste handler calls to turn a pasted YouTube URL
    # into an attachable it can insert (design spec section 8) -- inside
    # `mount_avo` so it inherits the same session gate as the page itself,
    # same reasoning as the reorder endpoint above.
    post "youtube_embeds", to: "youtube_embeds#create", as: :youtube_embeds

    # Admin-only mind graph (design spec section 9): Post nodes + PostRelation
    # edges, rendered client-side as a force-directed graph.
    get "mind_graph", to: "tools#mind_graph", as: :mind_graph

    # The setup wizard's system check, re-runnable later (design spec
    # 2026-09-26 §5).
    get "system_status", to: "tools#system_status", as: :system_status
  end
  resource :session
  resources :passwords, param: :token
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # First-run setup wizard (design spec 2026-09-26 §4). SetupController
  # itself 404s once setup is complete.
  get "setup", to: "setup#index", as: :setup
  get "setup/:step", to: "setup#show", as: :setup_step
  patch "setup/:step", to: "setup#update"

  # The MCP server (design spec section 10), bearer-token authenticated
  # (McpController#authenticate) -- declared here, before the public-site
  # catch-all below, or "/mcp" would be swallowed as a page path instead.
  post "mcp", to: "mcp#create"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Signed-in preview of unpublished pages and posts (spec §6.4) -- its own
  # URL space, so the public routes below can stay session-free and cacheable.
  # Two routes for the same reason the public site has two: an optional
  # `(/:locale)` would leave "about" in /preview/about to be read as a locale.
  get "preview/:locale(/*path)", to: "preview#show", constraints: LocaleRouteConstraint,
    defaults: { path: "" }, format: false, as: :localized_preview
  get "preview(/*path)", to: "preview#show", defaults: { path: "" }, format: false, as: :preview

  # Every locale is reachable under its own prefix (e.g. /de/about), including
  # whichever one is currently the site's default -- but a default-locale
  # prefix isn't the *canonical* URL for that content; PagesController
  # redirects it to the unprefixed route below, since SiteSetting's own
  # default_locale is a runtime setting this route can't see.
  #
  # Declared before the unprefixed routes below so an explicit "/de/..."
  # always matches here first: Rails tries routes in declaration order, and
  # "de" satisfies this route's locale constraint before the catch-all ever
  # gets a chance to read it as a page path instead.
  #
  # `format: false` suppresses the `(.:format)` group Rails otherwise appends
  # to every route. The site serves exactly one representation of a page, so
  # there is no format to negotiate -- and leaving the group in place breaks
  # this route in both directions, because a dot in the final segment is what
  # triggers it:
  #
  #   - "/de/about.json" on a real page still matches, so the controller finds
  #     the page and renders `show` in a format that has no template.
  #     `ActionView::MissingTemplate` is absent from
  #     `ActionDispatch::ExceptionWrapper.rescue_responses`, so it is mapped to
  #     no status and reaches the visitor as an uncaught 500 -- on a URL any
  #     crawler can construct.
  #   - A page whose slug legitimately contains a dot ("/v1.0") has its own
  #     trailing characters sliced off into `params[:format]`, so it 404s at
  #     the exact path `Page#full_path` publishes and config/sitemap.rb hands
  #     to search engines.
  #
  # The glob segment is wrapped in an optional group rather than left bare: a
  # `defaults: { path: "" }` alone does *not* make `*path` optional -- Journey
  # still requires at least one character for it, so "/de/" (which Rails
  # normalizes to "/de") would raise a routing error and that locale's root
  # would be unreachable. `(/*path)` makes the segment genuinely optional.
  # `constraints: LocaleRouteConstraint` (not a fixed regex): which locales
  # this route actually matches is a runtime setting (site_settings.locales,
  # spec §4.4), so it can't be hard-coded here the way `:path`'s absence of a
  # constraint can. `LocaleRouteConstraint#matches?` calls `Locales.enabled?`
  # per request; a locale that fails it is not an error -- the router simply
  # tries the next route, which is exactly what lets "/fr/about" fall through
  # to the unprefixed catch-all below (and then 404 there, since "fr/about"
  # is not itself a page) the moment "fr" is disabled, with no deploy needed.
  get ":locale(/*path)", to: "pages#show", constraints: LocaleRouteConstraint, as: :localized_page,
    defaults: { path: "" }, format: false

  # No locale prefix at all: served in the site's current default locale
  # (SiteSetting#default_locale, read per request by PagesController). Two
  # routes rather than one optional-locale route, deliberately -- a single
  # `"(/:locale)(/*path)"` pattern leaves Rails to decide for itself whether
  # a first segment like "de" is a locale or a page slug, which is exactly
  # the kind of routing ambiguity `format: false` above was already added to
  # close off one instance of; two separate, explicitly-ordered routes have
  # no such ambiguity to resolve.
  #
  # `root` on its own (rather than folding "/" into the `*path` glob below)
  # because an unwrapped `get "*path"` requires at least one character, the
  # same Journey behavior the locale route above works around with `(/*path)`
  # -- but here there's no static segment ahead of the glob to wrap it against,
  # so the homepage gets its own route instead.
  root to: "pages#show", format: false
  get "*path", to: "pages#show", as: :page, format: false
end
