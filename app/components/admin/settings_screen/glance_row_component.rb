module Admin
  module SettingsScreen
    # One row of the "At a glance" rail (`GlanceComponent`): a same-page
    # link to its card's heading (`#mail`), with the section's chip, its
    # name and its state. Only the four sections with a state have a row.
    #
    # - Languages: how many the site has, and which is the default (named
    #   in its own language, as the Languages card names it); no state chip,
    #   since a count is no state.
    # - AI translation: `AiState`, the word and tone the key's chip says;
    #   after a Test connection on this visit (`ai_result:`), its result.
    # - Mail: `MailSettings#state` in `MailStateComponent::TONES`, with the
    #   Mail card's words.
    # - Images: Ready, the count waiting to be made with the saved settings,
    #   the count that failed (both chips when both), or No images yet.
    #
    # Each row is its own element (`id_for`), so an answer that changes one
    # state (Test connection, Send test mail, a key or a login saved)
    # replaces that row and no other. It reads only what it is handed: the
    # screen has already read the settings row, the mail settings, the
    # images' counts and the languages, so the rail costs no statement.
    #
    # The link is a plain fragment link, as the nav's are: a jump within the
    # page leaves nothing, so the leave guard never asks about it. The state
    # chips are text and take no focus, so the keyboard passes over a row in
    # one step.
    class GlanceRowComponent < Admin::AdminComponent
      SECTIONS = %w[languages ai mail images].freeze

      def self.id_for(section_id) = "settings-glance-#{section_id}"

      def initialize(section:, site_setting:, mail_settings:, images_progress:, locales:, default:, ai_result: nil)
        raise ArgumentError, "the Settings section #{section.id.inspect} has no row at a glance" unless SECTIONS.include?(section.id)

        @section = section
        @site_setting = site_setting
        @mail_settings = mail_settings
        @images_progress = images_progress
        @locales = locales
        @default = default
        @ai_result = ai_result
      end

      def languages? = section.id == "languages"

      def language_count = glance("languages.count", count: locales.size)

      def default_line = glance("languages.default", language: ::Locales.name(default, native: true))

      def word = t(CardComponent.word_key(section))

      # The state chips' tones and words, in the order they are drawn.
      def chips
        case section.id
        when "languages" then []
        when "ai"
          state = AiState.of(site_setting, result: ai_result)
          [ [ AiState.tone(state), AiState.word(state) ] ]
        when "mail"
          state = mail_settings.state
          [ [ MailStateComponent::TONES.fetch(state), t("admin.mail.states.#{state}.word") ] ]
        when "images" then image_chips
        end
      end

      private

      attr_reader :section, :site_setting, :mail_settings, :images_progress, :locales, :default, :ai_result

      # The rail's words are the rail's (`glance.*`), read by full key: this
      # component's own scope would be `glance_row`.
      def glance(key, **options) = t("admin.components.settings_screen.glance.#{key}", **options)

      # Waiting is what is neither made with the saved settings nor failed:
      # a failed image is counted once, as failed.
      def image_chips
        total, made, failed = images_progress.values_at(:total, :made, :failed)
        return [ [ :off, glance("images.none") ] ] if total.zero?

        waiting = total - made - failed
        chips = []
        chips << [ :warn, glance("images.waiting", count: waiting) ] if waiting.positive?
        chips << [ :danger, glance("images.failed", count: failed) ] if failed.positive?
        chips.presence || [ [ :ok, glance("images.ready") ] ]
      end
    end
  end
end
