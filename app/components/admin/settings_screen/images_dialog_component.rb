module Admin
  module SettingsScreen
    # The confirmation behind the Images card's "Regenerate images...": it says
    # how many images will be made again with the SAVED settings, and its form
    # posts to `SettingsController#regenerate_images`. Drawn after the Settings
    # form, never inside it (forms do not nest).
    class ImagesDialogComponent < Admin::AdminComponent
      def initialize(progress:)
        @progress = progress
      end

      # Images not made with the saved settings, the ones that could not be
      # made included: what the press queues.
      def pending = @progress[:total] - @progress[:made]
    end
  end
end
