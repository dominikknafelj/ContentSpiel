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
  # `AccessControlHelper` gives every component the same `can?`/`can_edit?`
  # a CS Studio view has (access-control design spec §5), asked of
  # `Current.actor` -- so a button's visibility is decided where it's
  # rendered, not threaded through every constructor as a flag.
  class AdminComponent < ViewComponent::Base
    include SetupHelper
    include AccessControlHelper
    # `dialog_trigger(id)`: the `data:` that opens a dialog (no inline JS).
    include Admin::DialogHelper

    # The site's name in the default language -- the shell's wordmark
    # subline (handoff StudioSidebar) and the sign-in screens' eyebrow. The
    # default language, never the editor's current one: the shell is the
    # same whichever language a screen is being edited in.
    def site_name = ::Locales.read(Current.site, :title, locale: ::Locales.default)
  end
end
