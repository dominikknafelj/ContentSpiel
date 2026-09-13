Rails.application.routes.draw do
  mount_avo
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
  root to: redirect("/en/")

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
  get ":locale(/*path)", to: "pages#show", constraints: { locale: /en|de|es/ }, as: :page, defaults: { path: "" }
end
