module Admin
  # The Settings module's own form (cs-studio spec §6.1, Task 8): title,
  # tagline, logo (the explicit-remove pattern), social link rows, the
  # default language and the trash retention period (trash spec §4.4,
  # plain `<input type="number">`, `0` meaning never -- `SiteSetting#
  # trash_retention_days`'s own numericality validation is what a negative
  # value comes back as a per-field error from) -- one autosaving `<form>`,
  # same shape as `Admin::PageSettingsFormComponent`.
  #
  # The title and tagline are translated (translation helpers spec §5), so
  # like a page's settings form this shows the language switcher (with its
  # missing/outdated markers, `Translations::Status.switcher_locales`), the
  # editing language's own value in each input and the default
  # language's original beside it, with the "Original changed" note where
  # it applies. Everything else on the form is one value for the whole
  # site: it renders once, the same in every language, and is resent with
  # every autosave whichever language is showing.
  class SettingsFormComponent < AdminComponent
    ID_PREFIX = "settings"

    # The one element a `default_locale` change replaces wholesale
    # (`Admin::SettingsController#update`).
    DOM_ID = "settings-form".freeze

    def initialize(site_setting:, locale: ::Locales.default)
      @site_setting = site_setting
      @locale = locale.to_s
    end

    # The title/tagline in the language being edited -- the per-locale
    # Mobility reader, never a fallback: a blank German tagline has to show
    # as blank here, not as the English one (`Admin::PageSettingsForm
    # Component#value`'s comment).
    def value(field) = site_setting.public_send(field, locale: locale)

    # The default-language value shown beside a translated field in any
    # other language; nil in the default language itself, which is what
    # tells `Admin::Columns::Base#show_original?` there's nothing to show.
    def original(field)
      return nil if locale == ::Locales.default

      site_setting.public_send(field, locale: ::Locales.default)
    end

    # See `Admin::PageSettingsFormComponent#translation`. The Settings
    # module as a whole needs `settings.manage` -- the same right
    # `Translations::Confirm` asks for a site field -- so anyone seeing this
    # form may confirm.
    def translation(field) = Admin::EditorScreen::ReferenceCardComponent.options_for(site_setting, field, locale: locale, confirmable: true)

    def missing_locales = switcher_locales[:missing]

    def outdated_locales = switcher_locales[:outdated]

    # See `Admin::EditorScreen::HeaderComponent#switcher_locales`.
    def switcher_locales = @switcher_locales ||= Translations::Status.switcher_locales(site_setting)

    def language_url
      ->(code) { helpers.admin_settings_path(**(code.to_s == ::Locales.default ? {} : { locale: code })) }
    end

    # Always names the language it was rendered in -- even the default
    # one. The default language is itself a field on this form: without
    # the explicit `locale`, the autosave right after an editor switched
    # the default to German would resolve `admin_locale` to German and
    # write the English title still showing in the input over the German
    # one (review fix round 1).
    def form_url = helpers.admin_settings_path(locale: locale)

    def status_id = "#{ID_PREFIX}-save-status"

    def base_updated_at_id = "#{ID_PREFIX}-base-updated-at"

    def base_updated_at_value = site_setting.updated_at.iso8601(6)

    def logo_section_id = "#{ID_PREFIX}-logo-section"

    def field_id(field) = "#{ID_PREFIX}-#{field}"

    def field_html_name(field) = "site_setting[#{field}]"

    def errors_id(field) = Admin::FieldComponent.error_id(ID_PREFIX, field)

    # Restricted to the site's own enabled languages (spec §6.1) -- an
    # admin picking a default the site can't actually serve at its own root
    # would make every unprefixed page unreachable (`SiteSetting#default_
    # locale_is_enabled`'s own comment). Native names, the same as the
    # setup wizard's own language picker (`SetupHelper#language_options`),
    # since this is naming languages for whoever picks them, not describing
    # them in English.
    def default_locale_options
      ::Locales.enabled.map { |code| [ "#{::Locales.name(code, native: true)} (#{code.upcase})", code ] }
    end

    # Every zone `ActiveSupport::TimeZone` knows (dashboard spec §5), each
    # labelled with its current UTC offset the way `ActiveSupport::
    # TimeZone#to_s` already formats it ("(GMT+01:00) Berlin") -- the same
    # label the Rails zone-name select helper elsewhere in Rails apps
    # shows, so there's nothing CS Studio-specific to maintain here.
    #
    # The stored value is always among the options (final fix wave, I2):
    # autosave resends the whole form, so a stored value no option matched
    # would make the browser select -- and the next title edit save -- the
    # first option instead. An IANA identifier selects its Rails name (what
    # `SiteSetting#normalize_time_zone` would store it as anyway); anything
    # else written around the model is listed as itself, so it's resent
    # unchanged.
    def time_zone_options
      options = ::ActiveSupport::TimeZone.all.map { |zone| [ zone.to_s, zone.name ] }
      return options if options.any? { |_, name| name == selected_time_zone }

      [ [ ::ActiveSupport::TimeZone[selected_time_zone.to_s]&.to_s || selected_time_zone.to_s, selected_time_zone ], *options ]
    end

    def selected_time_zone
      stored = site_setting.time_zone.to_s
      ::ActiveSupport::TimeZone::MAPPING.key(stored) || stored
    end

    # Every registered provider by name (`AI::Providers`, translation
    # helpers spec §6.2), plus whatever is stored even if it's no longer
    # registered (a removed plugin's) -- like `time_zone_options`, so an
    # autosave resends the stored value instead of the browser silently
    # switching to the first option.
    def ai_provider_options
      names = ::AI::Providers.names
      stored = site_setting.ai_provider
      stored.present? && !names.include?(stored) ? [ stored, *names ] : names
    end

    # The form always renders a few name/URL rows (spec §4.1's own "site.
    # html.erb" convention, carried over verbatim): a row missing either
    # half is silently dropped on save (`SiteSetting#social_link_rows=`),
    # not saved as a broken link.
    def social_link_rows
      links = site_setting.social_links.to_a
      links + Array.new([ 4 - links.size, 1 ].max) { [ "", "" ] }
    end

    private

    attr_reader :site_setting, :locale
  end
end
