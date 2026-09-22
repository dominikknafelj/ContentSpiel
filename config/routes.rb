Rails.application.routes.draw do
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
  end
  resource :session
  resources :passwords, param: :token
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

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
  get ":locale(/*path)", to: "pages#show", constraints: { locale: /en|de|es/ }, as: :localized_page,
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
