module Admin
  module SettingsScreen
    # The Languages card: one row per enabled language -- a drag handle, the
    # native name with its public path (`/` for the default, `/<code>` for
    # the rest), a "Default" badge or a "Make default…" button, a "Falls back
    # to" select and "Turn off…" -- and "Add language" below. Rendered only
    # for `languages.manage`.
    #
    # TWO KINDS OF CONTROL, and which form each belongs to is the point:
    #
    # PENDING -- fields of the one Settings form, saved by its save bar: the
    # ORDER (a hidden `site_setting[languages][][code]` per row, in row order,
    # plus the one tracked `site_setting[language_order]` that makes a
    # reorder a single counted change; see `admin--settings--sortable-rows`) and each
    # row's FALLBACK (`site_setting[languages][][fallback]`).
    #
    # INSTANT -- Default, Turn off and Add, each a form of its own that sits
    # OUTSIDE the Settings form (`Admin::SettingsScreen::LanguageDialogsComponent`;
    # forms can't nest) and is reached from here by the `form=` attribute or a
    # dialog trigger. They answer with a 303 to the screen, which reloads it, so
    # they are disabled while the main form has unsaved changes
    # (`admin--saving--pending-lock`): otherwise the reload would throw the
    # typed changes away. Being instant, none is the primary: the save bar's
    # Save is the screen's one. Make default… and Add language are secondary,
    # Turn off… the danger text.
    #
    # The default language is NOT a radio group: a radio moves on every arrow
    # key, and each move would open the "Make <Name> the default?" dialog, so a
    # keyboard user could not walk the group without being asked. The default
    # row carries the neutral "Default" badge; every other row a "Make
    # default…" button that opens that dialog.
    #
    # `values:` -- `Values` (typed order and fallbacks beat stored).
    class LanguagesCardComponent < Admin::AdminComponent
      ADD_FORM = "language-add-form".freeze

      def self.default_dialog_id(code) = "language-default-dialog-#{code}"

      def self.off_dialog_id(code) = "language-off-dialog-#{code}"

      def initialize(site_setting:, values:)
        @site_setting = site_setting
        @values = values
      end

      def rows = values.language_rows

      def default?(code) = code == site_setting.default_locale.to_s

      def name(code) = ::Locales.name(code, native: true)

      # The public path as the card shows it (a label, not a link): `/` for the
      # default, `/<code>` otherwise. Joined rather than interpolated, which
      # `PublicUrlsGuardTest` would take for a hand-built public URL.
      def path(code) = default?(code) ? "/" : [ "", code ].join("/")

      # What the save bar calls a row's fallback: "Deutsch: Falls back to".
      def fallback_name(code) = t("admin.components.ui.save_bar.per_language", language: name(code), label: t(".names.fallback"))

      def order_value = rows.map { |row| row[:code] }.join(",")

      # "None (default)" first, then every OTHER enabled language.
      def fallback_options(code)
        [ [ t(".no_fallback"), "" ] ] + (rows.map { |row| row[:code] } - [ code ]).map { |other| [ name(other), other ] }
      end

      def addable_options
        enabled = site_setting.locale_codes
        helpers.language_options.reject { |_label, code| enabled.include?(code) }
      end

      private

      attr_reader :site_setting, :values
    end
  end
end
