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
  # A component browser for the ViewComponents under app/components
  # (open-types spec §5), development only -- never mounted in test or
  # production, and declared here, before the public catch-alls below, so
  # "/lookbook" isn't swallowed as a page path first. Renders through
  # `ComponentPreviewsController` (config/initializers/view_component.rb),
  # the same controller the preview smoke test
  # (test/components/previews_test.rb) uses, so what an editor sees in
  # Lookbook and what that test asserts never raises are the same rendering
  # path.
  mount Lookbook::Engine, at: "/lookbook" if Rails.env.development?

  # CS Studio, the admin (cs-studio spec §3). Its path is configurable
  # (ContentSpiel::ADMIN_PATH) and sign-in lives under it, so the public site
  # advertises no login page. Declared before /preview and the public
  # catch-alls, which would otherwise swallow it as a page path.
  scope ContentSpiel::ADMIN_PATH, module: :admin, as: :admin do
    get "sign-in", to: "sessions#new", as: :sign_in
    post "sign-in", to: "sessions#create"
    delete "sign-out", to: "sessions#destroy", as: :sign_out
    resource :password, only: %i[new create]
    get "password/:token/edit", to: "passwords#edit", as: :edit_password
    patch "password/:token", to: "passwords#update", as: :update_password

    # The Pages module (cs-studio spec §4.1/§5.1). `member` adds the three
    # publish-state actions the record header's own buttons post to
    # (Publish now / Unpublish / Schedule…, spec §5.1) -- each its own
    # one-shot POST, deliberately outside the settings form's autosave
    # (`Admin::PagesController`'s own class comment explains why).
    resources :pages, only: %i[index new create show update destroy] do
      member do
        post :publish
        post :unpublish
        post :schedule
      end

      # A page's blocks (cs-studio spec §5.1/§6.1, Task 5): nested under the
      # page rather than a top-level resource, since a block is meaningless
      # without the page it's on and every one of these actions already
      # needs `page_id` to scope its lookup (`Admin::ContentBlocksController
      # #set_page`) -- there is no "show a block on its own" screen for
      # `:show`/`:index` to serve. `reorder` is a `collection` route (it
      # names every block to keep, not one) the same way the page tree's own
      # move endpoint is `resource :tree`, not nested under one page;
      # `duplicate` is a `member` route since it always starts from exactly
      # one existing block.
      resources :content_blocks, only: %i[create update destroy] do
        collection { patch :reorder }
        member { post :duplicate }
      end
    end

    # The page tree's own move endpoint (cs-studio spec §4.2), a `resource`
    # (singular) rather than nested under `pages` -- a move names the page
    # being dragged in its own params (`page_id`), not the URL, since the
    # same one PATCH target serves every node in the tree. `update` only
    # (final-fixes round, finding 11): the tree's own GET is already free on
    # every Pages view via `content_for :tree` -- a bare `:show` here
    # answered a plain GET with a Turbo Stream body, which nothing in this
    # app ever actually requests (no `<turbo-frame src="...">` points at
    # it) and no browser navigating here directly could even render (a
    # `<turbo-stream>` response isn't valid, renderable HTML for a
    # top-level GET).
    resource :tree, only: %i[update], controller: :tree

    # The Tiptap editor's own upload button (design spec §4.1/§4.2): POSTs
    # a multipart `file`, gets back `{ id, url }` (201) or `{ errors }`
    # (422) -- `create` only, there is no listing/edit/destroy screen for a
    # `MediaAsset` yet (design spec §4.2's "Relation to open types": that
    # arrives with the media library sub-project).
    resources :media_assets, only: :create

    # The internal-link picker's own search (design spec §4.1/§4.2): a
    # `GET`, not nested under `pages`/`posts` -- it searches across both at
    # once (`?type=` narrows to one), so there is no single owning resource
    # to nest it under the way `content_blocks` nests under `pages`.
    get "link_targets", to: "link_targets#index"

    # The Posts module (cs-studio spec §4.1/§5.2): a flat, filterable list
    # (no tree column of its own -- a post has no parent/child structure the
    # way a page does) plus the post editor. `member` adds the same three
    # publish-state actions the page editor's own record header posts to
    # (Publish now / Unpublish / Schedule…, `Admin::PagesController`'s own
    # comment explains why each is a one-shot POST kept deliberately outside
    # the post form's own autosave, not folded into `update`).
    resources :posts, only: %i[index new create show update destroy] do
      member do
        post :publish
        post :unpublish
        post :schedule
      end
    end

    # The Tags module (cs-studio spec §4.1/§5.3): a flat list with no
    # `:show`/`:new`/`:create` of its own -- a tag has no editor screen, only
    # an inline rename (`:update`) and a delete (`:destroy`) from the list
    # itself; new tags are only ever created in passing, through a post's own
    # `tag_names` (`Posts::Save`).
    resources :tags, only: %i[index update destroy]

    # The Pages module is CS Studio's home (cs-studio spec §4.1) -- replaces
    # the placeholder `home#show` this task's brief removes.
    root to: "pages#index"
  end
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
