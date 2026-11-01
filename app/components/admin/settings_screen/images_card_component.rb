module Admin
  module SettingsScreen
    # The Images card (docs/reference/media.md, "Settings -> Images"), after
    # Publishing, for `settings.manage`.
    #
    # - Format (WebP or AVIF, a segmented control), the quality of each format,
    #   the widths (ONE field of comma-separated numbers) and the largest
    #   upload are fields of the one Settings form, saved with its save bar.
    #   AVIF is opt-in: it is disabled, with its reason, on a server that
    #   cannot write it, and where it is offered a line says that browsers
    #   too old to show it then show nothing.
    # - Saving changes no image. The card says how many images were NOT made with
    #   the saved settings ("12 images were made with other settings", nothing
    #   when none) and how many could not be made (a link to System status for
    #   `status_link`); "Regenerate images..." is the press that makes
    #   the rest. It sits outside the form (a button of its own, opening the
    #   dialog `ImagesDialogComponent` renders after the form, which has the
    #   POST), so a press never counts as an unsaved change.
    #
    # `progress` is `Media::RenditionProgress#counts` for the SAVED settings
    # (`{ total:, made:, failed: }`); `values` what the fields show (typed
    # beats stored after a refused save); `errors` the refused save's
    # `ActiveModel::Errors`, or nil.
    class ImagesCardComponent < Admin::AdminComponent
      FIELDS = %i[image_format image_quality_webp image_quality_avif image_widths image_max_upload_mb].freeze
      DIALOG = "settings-images-regenerate-dialog".freeze

      def initialize(values:, progress:, avif_available:, errors: nil, status_link: false)
        @values = values
        @progress = progress
        @avif_available = avif_available
        @errors = errors
        @status_link = status_link
      end

      # Whether the failed count links to System status: the viewer holds
      # `system_status.view` (the caller asks), else it is plain text.
      def status_link? = @status_link

      def status_path
        helpers.admin_system_status_path(**(helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}))
      end

      # Images not made with the saved settings (the failed ones included).
      def other_settings = total - made

      def avif_available? = @avif_available

      # The format shown chosen: what was typed or stored. An AVIF stored on a
      # server that has since lost the encoder stays shown as chosen (and
      # disabled) rather than silently reading as WebP.
      def format = ImageSettings::FORMATS.include?(value(:image_format)) ? value(:image_format) : ImageSettings::DEFAULTS[:format]

      def value(name) = values.image(name).to_s

      def input_id(name) = "settings-#{name}"

      def field_errors(name) = errors.respond_to?(:full_messages_for) ? errors.full_messages_for(name) : []

      def segment_class = Admin::Fields::SelectField::SEGMENT_CLASS

      def total = progress[:total]

      def made = progress[:made]

      def failed = progress[:failed]

      def width_range = ImageSettings::WIDTH_RANGE

      def quality_range = ImageSettings::QUALITY_RANGE

      def upload_range = ImageSettings::UPLOAD_MB_RANGE

      def width_count = ImageSettings::WIDTH_COUNT

      private

      attr_reader :values, :progress, :errors
    end
  end
end
