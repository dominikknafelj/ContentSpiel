module Admin
  # The strings a script shows, handed over by the server (docs/reference/
  # i18n.md, "A string a script shows"). `data-messages="<%= messages_data(
  # "components.save_status.saving", "components.save_bar.changes") %>"` on the
  # element a controller lives on (or on <body>, for what every screen's
  # scripts share), and the controller reads it through
  # `messages(element).t(key, { count, name })` from `i18n/messages.js`
  # (which asks each `data-messages` ancestor in turn, then <body>).
  #
  # `keys` are dotted paths below `admin` -- always `admin`, the one convention
  # for the server and the script alike; each is looked up with `I18n.t(...,
  # raise: true)` -- whatever the environment's missing-translation setting,
  # an unknown key is an error at render time, never a script that shows
  # "translation missing". A key that holds `one:`/`other:` (or whichever
  # plural categories the locale's file defines) is sent whole, with `%{count}`
  # and any other `%{name}` left in for the script to fill; a plain string
  # is sent as it is. The one reserved key, `@locale`, names the language the
  # texts are in: the script picks a plural category with `Intl.PluralRules` for
  # it, so a German or Slavic file only has to define the categories it needs.
  #
  # Mixed into every view by Rails' default `helper :all` and into
  # `Admin::AdminComponent` by hand. Only I18n is used here, never a view's
  # `t`, so it behaves the same in both.
  module MessagesHelper
    # What the scripts that run on every CS Studio screen show -- the autosave
    # status line and its Retry, the save footer's count and the leave dialog's
    # sentences, the pending-lock hint, the toasts a failed drop raises --
    # written once on <body> (`layouts/admin`), where a script that finds no
    # nearer `data-messages` reads them. Keys are relative to `admin`.
    # `notes.script.*` are `admin--notes`': that controller is on <body>
    # itself, so <body> is the only place its messages can be.
    SCRIPT_MESSAGES = %w[
      components.save_status.saving components.save_status.saving_live components.save_status.retrying
      components.save_status.offline components.save_status.signed_out components.save_status.retry
      components.save_bar.changes components.save_bar.unsaved components.save_bar.no_changes components.save_bar.blocked
      components.toast.order_failed components.toast.dropped
      layout.leave_dialog.body layout.leave_dialog.body_with_count
      notes.script.marker.add notes.script.marker.open notes.script.marker.selection notes.script.total notes.script.delete_warning notes.script.delete_section_warning
    ].freeze

    def admin_script_messages = messages_data(*SCRIPT_MESSAGES)

    def messages_data(*keys)
      keys.flatten.each_with_object({ "@locale" => I18n.locale.to_s }) do |key, messages|
        messages[key.to_s] = I18n.t("admin.#{key}", raise: true).then { |value| value.is_a?(Hash) ? value.transform_keys(&:to_s) : value }
      end.to_json
    end
  end
end
