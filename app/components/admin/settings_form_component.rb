module Admin
  # The Settings module's own form (cs-studio spec §6.1, Task 8): title,
  # tagline, logo (the explicit-remove pattern), social link rows, the
  # default language and the trash retention period (trash spec §4.4,
  # plain `<input type="number">`, `0` meaning never -- `SiteSetting#
  # trash_retention_days`'s own numericality validation is what a negative
  # value comes back as a per-field error from) -- one autosaving `<form>`,
  # same shape as `Admin::PageSettingsFormComponent`. Unlike a page/post,
  # none of `SiteSetting`'s own columns are translated (Mobility), so this
  # renders through `Admin::Columns::PlainColumnComponent`/
  # `ImageColumnComponent` with no `locale`/`original` at all -- those
  # components already treat both as optional for exactly this case.
  class SettingsFormComponent < AdminComponent
    ID_PREFIX = "settings"

    def initialize(site_setting:, url_options: {})
      @site_setting = site_setting
      @url_options = url_options
    end

    def form_url = helpers.admin_settings_path(**url_options)

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
    def time_zone_options
      ::ActiveSupport::TimeZone.all.map { |zone| [ zone.to_s, zone.name ] }
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

    attr_reader :site_setting, :url_options
  end
end
