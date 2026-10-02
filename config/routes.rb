Rails.application.routes.draw do
  # While setup is required, every route below is unreachable (design spec
  # 2026-09-26 §3): these two catch-alls are declared first, so they win over
  # CS Studio and the public page routes. A lambda, so the constant is only
  # resolved per request (never while routes load during boot).
  constraints(->(request) { Setup::RedirectConstraint.matches?(request) }) do
    match "/", to: redirect("/setup", status: 302), via: :all, as: :setup_required_root
    match "*path", to: redirect("/setup", status: 302), via: :all, format: false, as: :setup_required
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
    # (422) -- `create` only, kept separate from the Media module's own
    # `media` resource just below: there's no page or post this upload
    # belongs to yet at editing time, so it has no id to nest under, and
    # `Admin::MediaAssetsController#create` is the editor's own, narrower
    # JSON-in-JSON-out contract, not the module's own browse/edit screens.
    resources :media_assets, only: :create

    # The Media module (media library design spec §6, Task 7): browse,
    # upload, edit and delete library images, all through `Media::Upload`/
    # `Save`/`Destroy`. `index` is the grid (search, filters, pagination);
    # `show` is one image's detail panel; `create` is the grid's own
    # multi-file upload (`admin--media-upload`, one request per file, per
    # the global constraints' own ruling); `update`/`destroy` save/delete.
    # `resources :media` singularizes to "medium" for its member routes
    # (`admin_medium_path`) -- the plain, if slightly odd-looking, Rails
    # default for this one English word, left as-is rather than overridden
    # with an `:as` this app has no other resource needing.
    resources :media, only: %i[index show create update destroy]

    # Trash (trash spec §7). `:type` is page|post|media -- one screen for
    # three models, so the item is addressed by type and id rather than by a
    # resource per model. The constraint is what turns any other `:type`
    # into a routing 404 before `Admin::TrashController` is ever reached.
    get "trash", to: "trash#index", as: :trash
    delete "trash", to: "trash#empty", as: :empty_trash
    post "trash/:type/:id/restore", to: "trash#restore", as: :restore_trash_item, constraints: { type: /page|post|media/ }
    delete "trash/:type/:id", to: "trash#purge", as: :trash_item, constraints: { type: /page|post|media/ }

    # "Mark as up to date" for an outdated translation (translation helpers
    # spec §3.4/§4): one endpoint for every translatable record kind, named
    # by `record_type`/`record_id` in the params (the editor's button posts
    # them in its `formaction`), the way the trash addresses its items by
    # type rather than one nested route per model.
    post "translations/confirm", to: "translation_confirmations#create", as: :translation_confirmation

    # The Translations overview (translation helpers spec §4): what's
    # missing or outdated in `?locale=` (a target language), optionally
    # narrowed by `?type=page|post|media`, paged by `?offset=`. A plain
    # `get` rather than `resources :translations, only: :index`, so the
    # AI suggestion action (Task 8) can join the same controller on a
    # route of its own without a resource's implied member routes.
    get "translations", to: "translations#index", as: :translations

    # AI translation suggestions (translation helpers spec §6.4): the
    # editor's Translate buttons post the record (`record_type`/
    # `record_id`, like the confirm endpoint above), `fields[]`, the target
    # `locale` and `inputs[field]` (the input each suggestion is for), and
    # get Turbo Streams back. A POST although nothing is saved: it spends
    # the provider's quota and records an `ai.translated` event.
    post "translations/suggest", to: "translations#suggest", as: :translation_suggestions

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

    # The Settings module (cs-studio spec §6.1, Task 8): the `SiteSetting`
    # singleton's own autosaving form (title, tagline, logo, social links,
    # default language) -- `resource` (singular), like the page tree's own
    # `resource :tree`, since there's exactly one settings row to show or
    # update, never a collection or an `:id` to route on.
    resource :settings, only: %i[show update] do
      # Translation helpers spec §6.2: checks the saved AI provider, model
      # and key with one tiny request, answered inline as a Turbo Stream.
      post :test_ai_connection
    end

    # The Languages module (cs-studio spec §6.1, Task 8), nested under
    # "settings" by *path* only (`scope`, not `namespace` -- the brief calls
    # for a plain `Admin::LanguagesController`, not `Admin::Settings::
    # LanguagesController`) so its URLs read as part of the Settings module
    # the way the spec's own module list ("Languages (settings/languages)")
    # names it. `create`/`destroy` are `Locales::Enable`/`Locales::Disable`
    # (one language at a time, by its code as `:id`); the bulk `update`
    # (fallbacks + reorder, `Locales::Configure`) has no `:id` of its own --
    # the languages screen's one form always submits every enabled
    # language's row together, the same way `ContentBlocks::Reorder` is
    # handed a complete order rather than a delta -- so it's a bare `patch`
    # on the collection path rather than a `resources` member/collection
    # action.
    scope "settings", as: "settings" do
      resources :languages, only: %i[index create destroy]
      patch "languages", to: "languages#update"
    end

    # The Users module (cs-studio spec §6.1, Task 8): list, new/create,
    # edit/update (email, and a password only when one was typed --
    # `Users::Save`), destroy (refused for the last user, `Users::Destroy`
    # -- `Admin::UsersController#destroy` is also where deleting *yourself*
    # ends your own session, since only the controller knows which request
    # this is). Invites stay on the roadmap (spec §6.1) -- there is no
    # separate "invite" action here.
    resources :users, only: %i[index new create edit update destroy]

    # The Groups module (access-control design spec §5): the list, the
    # editor (name, description, members, the permission matrix) and
    # delete (`Groups::Destroy`, which revokes the group's tokens). No
    # `:show` -- the editor is the group's page.
    resources :groups, only: %i[index new create edit update destroy]

    # "Change my password" (access-control design spec §5): the signed-in
    # user's own account, open to every user -- unlike the Users module,
    # which needs `users.manage`. Singular: it's always *your* account.
    get "account/password", to: "accounts#edit", as: :account_password
    patch "account/password", to: "accounts#update"

    # "Connect an AI assistant" (design spec §6.1, Task 9): the MCP bearer
    # tokens. No `:new`/`:show` -- "Create token" is one button on the list
    # that POSTs straight to `create`, and `create` *renders* the one-time
    # reveal itself (never a redirect to a `show`, which would need the raw
    # token to survive a second request somewhere -- see `Admin::
    # ApiTokensController#create`). `destroy` is revoke
    # (`ApiTokens::Revoke`): the row stays, marked revoked, for the list's
    # own "last used / IP" history.
    resources :api_tokens, only: %i[index create destroy]

    # System status and the mind graph (design spec §6.1, Task 9): one
    # read-only screen each, `resource` (singular) since neither has an
    # `:id` to route on. "Run again" on the status screen is a plain reload
    # of `show` -- `Setup::SystemCheck` runs on every request.
    resource :system_status, only: :show, controller: :system_status
    resource :mind_graph, only: :show, controller: :mind_graph

    # The audit log (access-control design spec §5 "Audit log module",
    # Task 9): a paginated, filterable list plus one event's own page.
    # `resources` (plural, unlike `system_status`/`mind_graph` above) since
    # each row has its own `:id` to route `show` on -- but only `:index`/
    # `:show`: `Audit::Event` is append-only (its own class comment), never
    # created, edited or destroyed through a CS Studio form.
    resources :audit_events, only: %i[index show]

    # "Create starter pages" on the Pages home (design spec §6.1, Task 9):
    # one POST, `StarterContent.create_pages_and_posts!`, idempotent.
    resources :starter_contents, only: :create

    # The dashboard is CS Studio's home (dashboard spec §3-§4, Task 2):
    # "Your work", "On the site" and quick create, open to every signed-in
    # user. The Pages module -- the tree and its own editor -- lives at
    # its own `/pages` (`resources :pages` above), no longer at the root.
    root to: "dashboard#show"
    # Quick draft (dashboard spec §4.1): a title and a content type, saved
    # through `Posts::Save` as an unpublished post, then opened in the
    # post editor.
    post "dashboard/draft", to: "dashboard#create_draft", as: :dashboard_draft
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
  #
  # The constraint (final fix wave, C) keeps Active Storage's own URLs out of
  # this catch-all: Rails draws the Active Storage routes *after* this file,
  # so without it `/rails/active_storage/blobs/...` -- every image a page,
  # post or rich-text body embeds -- was routed here and answered 404.
  root to: "pages#show", format: false
  get "*path", to: "pages#show", as: :page, format: false,
    constraints: ->(request) { !request.path.start_with?("#{ActiveStorage.routes_prefix}/") }
end
