module Admin
  module SettingsScreen
    # The Site card (round 3, Task 5; decision D6, handoff B32): the site's
    # title and tagline in EVERY enabled language at once, then the logo, the
    # time zone and the social links -- all fields of the one Settings form
    # (`#settings-form`), none of them autosaving.
    #
    # Every language's pair is in the page (`site_setting[translations][<code>]
    # [title|tagline]`, ids `settings-<code>-title`), one panel per language;
    # the language tabs in the header (`LanguageTabsComponent`, `mode:
    # :buttons`) only switch which panel is visible (`admin--settings-tabs`,
    # `hidden` and `aria-selected`) and never navigate, so switching tabs is
    # not a change and cannot trigger the leave guard. `locale:` is the tab
    # shown first (`?locale=`). A non-default language shows the original
    # beside each field in the editors' reference card, with the same
    # Translate / Suggest update / Still correct controls, and its own "Suggest
    # translations for N empty fields" -- which acts on the language that is
    # visible (`admin--translate` ignores fields inside a hidden panel).
    #
    # Everything below the pairs is one value for the whole site.
    class SiteCardComponent < Admin::AdminComponent
      PANEL_ATTR = "data-language-panel".freeze

      # `values:` -- `Values` (typed beats stored). `errors:` -- the
      # `ActiveModel::Errors` of a refused save, for the inline slots.
      def initialize(site_setting:, values:, locale:, errors: nil)
        @site_setting = site_setting
        @values = values
        @locale = locale.to_s
        @errors = errors
      end

      def codes = ::Locales.enabled

      def current?(code) = code == locale

      def default?(code) = code == ::Locales.default

      def panel_id(code) = "settings-panel-#{code}"

      def field_id(code, field) = "settings-#{code}-#{field}"

      def html_name(code, field) = "site_setting[translations][#{code}][#{field}]"

      # See `Admin::EditorScreen::HeaderComponent#switcher_locales`.
      def switcher_locales = @switcher_locales ||= Translations::Status.switcher_locales(site_setting)

      # The original beside a translated field, in any language but the default.
      def original(code, field)
        return nil if default?(code)

        site_setting.public_send(field, locale: ::Locales.default)
      end

      # See `Admin::PageSettingsFormComponent#translation`. Anyone seeing this
      # card holds `settings.manage`, the same right `Translations::Confirm`
      # asks for a site field.
      def translation(code, field) = Admin::EditorScreen::ReferenceCardComponent.options_for(site_setting, field, locale: code, confirmable: true)

      def tabs_data(code) = { "admin--settings-tabs-target": "tab", action: "admin--settings-tabs#select keydown->admin--settings-tabs#keydown", code: code }

      def errors_for(attribute) = errors ? errors.full_messages_for(attribute) : []

      # Every zone `ActiveSupport::TimeZone` knows (dashboard spec §5), each
      # labelled with its current UTC offset ("(GMT+01:00) Berlin").
      #
      # The stored value is always among the options: the form resends every
      # field, so a stored value no option matched would make the browser
      # select -- and the next save write -- the first option instead. An IANA
      # identifier selects its Rails name (what `SiteSetting#normalize_time_
      # zone` would store it as anyway); anything else written around the
      # model is listed as itself, so it's resent unchanged.
      def time_zone_options
        selected = values.time_zone
        options = ::ActiveSupport::TimeZone.all.map { |zone| [ zone.to_s, zone.name ] }
        return options if options.any? { |_, name| name == selected }

        [ [ ::ActiveSupport::TimeZone[selected.to_s]&.to_s || selected.to_s, selected ], *options ]
      end

      # A social link's row for the `<template>`: the same markup as a stored
      # one, its index a placeholder `admin--repeat-rows` fills in.
      TEMPLATE_INDEX = "__INDEX__".freeze

      private

      attr_reader :site_setting, :values, :locale, :errors
    end
  end
end
