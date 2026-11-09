module Admin
  # The stream that redraws one row of Settings' "At a glance" rail
  # (`Admin::SettingsScreen::GlanceRowComponent`), for the answers of the
  # Settings screen's instant actions: Test connection and Send test mail
  # (`Admin::SettingsController`), a key or a login saved or removed
  # (`Admin::CarriedBase`). Each answer that changes a state replaces its
  # card's part and, in the same answer, its rail row, so the two never
  # disagree. Only the AI and Mail rows change in place; the languages and
  # the images change through the form's save, which draws the screen anew.
  module GlanceRows
    extend ActiveSupport::Concern

    IN_PLACE = %w[ai mail].freeze

    private

    # `ai_result:` is a Test connection's result on this visit (`:connected`
    # or `:failed`), which the row says until the screen is drawn again.
    def glance_row_stream(section_id, site: Current.site, ai_result: nil)
      raise ArgumentError, "the rail's #{section_id.inspect} row is redrawn only with the screen" unless IN_PLACE.include?(section_id)

      row = Admin::SettingsScreen::GlanceRowComponent
      turbo_stream.replace(row.id_for(section_id), row.new(section: SettingsSections.find(section_id), site_setting: site,
        mail_settings: MailSettings.current(site), images_progress: nil, locales: Locales.enabled, default: Locales.default, ai_result: ai_result))
    end
  end
end
