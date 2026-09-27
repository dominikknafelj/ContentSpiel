module Admin
  # Base for every CS Studio admin view component (spec §4.3). Deliberately
  # its own base, not the public site's `ApplicationComponent`: that base
  # delegates public-theme helpers (`translated`, `page_url_path`, ...) that
  # no admin screen has any business calling, and admin renders through the
  # product Tailwind build (`app/assets/tailwind/application.css`)'s own
  # `--cs-*` tokens, never the public theme's `--th-*` ones (global
  # constraints). `SetupHelper` is mixed in so every admin input/label/button
  # reuses the exact class strings the setup wizard already established for
  # this same product chrome, rather than a second, drifting copy of them.
  class AdminComponent < ViewComponent::Base
    include SetupHelper
  end
end
