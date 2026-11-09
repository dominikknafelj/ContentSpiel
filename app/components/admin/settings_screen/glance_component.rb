module Admin
  module SettingsScreen
    # The "At a glance" rail of the Settings screen: the state of languages,
    # AI translation, mail and images, one `GlanceRowComponent` each, for the
    # sections the viewer's cards show (`SettingsSections.for`), so a viewer
    # who manages only the languages is told nothing of mail, the AI key or
    # the images. Then the hint that Settings save together.
    #
    # It stands in the document after the nav and before the cards at every
    # width; the stylesheet places it (`.admin-settings-layout`): a compact
    # card above the first card, and docked on the rail's ground beside the
    # cards from 1200px of the Settings area's own width. Nothing is stored:
    # a Test connection's result (`ai_result:`) is said on this visit only.
    class GlanceComponent < Admin::AdminComponent
      HEADING_ID = "settings-glance-heading".freeze

      def initialize(sections:, site_setting:, mail_settings:, images_progress:, locales:, default:, ai_result: nil)
        @sections = sections.select { |section| GlanceRowComponent::SECTIONS.include?(section.id) }
        @row = { site_setting: site_setting, mail_settings: mail_settings, images_progress: images_progress,
                 locales: locales, default: default, ai_result: ai_result }
      end

      def render? = sections.any?

      private

      attr_reader :sections, :row
    end
  end
end
