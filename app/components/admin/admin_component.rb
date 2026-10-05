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

    include Admin::SiteNameHelper
    # `messages_data(*keys)`: the strings a component's script shows,
    # as the JSON of a `data-messages` attribute (see that helper).
    include Admin::MessagesHelper

    # The component's own translation scope, from its class name:
    # `Admin::ConfirmDialogComponent` is `confirm_dialog`,
    # `Admin::EditorScreen::HeaderComponent` is `editor_screen.header`. Keys
    # live under `admin.components.<that>` (`config/locales/admin/
    # components.en.yml`, docs/reference/i18n.md).
    def self.translation_scope
      @translation_scope ||= name.delete_prefix("Admin::").delete_suffix("Component").underscore.tr("/", ".")
    end

    # `t(".cancel")` reads `admin.components.<translation_scope>.cancel`; any
    # other key is passed on untouched. ViewComponent's own `t` would resolve
    # the relative key to `admin.confirm_dialog_component.cancel` (its scope is
    # the class name underscored), so the relative key is made absolute first
    # and ViewComponent's `translate` then does what it does for an absolute
    # key: the view context's `t`, which marks a `_html` key safe and escapes
    # what is interpolated into it, pluralises on `count`, and raises on a
    # missing key where `config.i18n.raise_on_missing_translations` is on.
    # The scope is the INSTANCE's class: a `t(".x")` written in a base class
    # reads the subclass's scope, with no fallback to the ancestor's. A String
    # or Symbol key starting with a dot is rescoped; an Array of keys, or any
    # other key, is not. (A sidecar `.yml` would take over a key under its own scope; none exists,
    # and none should: one central file per scheme.)
    def translate(key = nil, **options)
      return super unless (key.is_a?(String) || key.is_a?(Symbol)) && key.to_s.start_with?(".")

      super("admin.components.#{self.class.translation_scope}#{key}", **options)
    end
    alias_method :t, :translate
  end
end
