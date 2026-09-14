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

  # The site has no unprefixed public URLs -- every page lives under a locale,
  # so "/" only exists to send a visitor to the default locale's root page.
  # Still declared with `root` rather than `get "/"` so that `root_url` keeps
  # resolving (Authentication#after_authentication_url falls back to it).
  # 302 rather than the `redirect` helper's default 301: a permanent redirect
  # is cached by browsers indefinitely and cannot be withdrawn from the client
  # side, so it is only safe once the mapping is genuinely permanent. Nothing
  # has launched publicly yet, and "/" may well come to serve a locale
  # negotiated from the request instead of always /en/ -- a 301 shipped now
  # would be stuck in the cache of everyone who ever hit it.
  root to: redirect("/en/", status: :found)

  # The public site: every page in the `Page` tree is served by this one route,
  # which hands `PagesController` a locale and the rest of the path to look up.
  #
  # Declared last because it is a catch-all -- the named routes above (/avo,
  # /session, /up, ...) have to win over it. The locale constraint keeps it from
  # swallowing unrelated top-level paths entirely: only the three locales the
  # site is published in (config.i18n.available_locales) reach the controller.
  #
  # The glob segment is wrapped in an optional group rather than left bare: a
  # `defaults: { path: "" }` alone does *not* make `*path` optional -- Journey
  # still requires at least one character for it, so "/en/" (which Rails
  # normalizes to "/en") raises a routing error and the homepage is unreachable.
  # `(/*path)` makes the segment genuinely optional, and the default is what
  # then supplies the "" the controller normalizes into "/".
  #
  # `format: false` suppresses the `(.:format)` group Rails otherwise appends
  # to every route. The site serves exactly one representation of a page, so
  # there is no format to negotiate -- and leaving the group in place breaks
  # this route in both directions, because a dot in the final segment is what
  # triggers it:
  #
  #   - "/en/about.json" on a real page still matches, so the controller finds
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
  # With the group gone, the whole remainder of the URL is the glob, and both
  # cases are simply a path that either names a page or doesn't.
  get ":locale(/*path)", to: "pages#show", constraints: { locale: /en|de|es/ }, as: :page,
    defaults: { path: "" }, format: false
end
