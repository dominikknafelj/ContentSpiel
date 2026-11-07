module Admin
  module Ui
    # `Admin::Ui::SaveStatusComponent`: every autosave state, in its own
    # words.
    class SaveStatusComponentPreview < ViewComponent::Preview
      def idle
        render Admin::Ui::SaveStatusComponent.new(id: "save-status-idle", state: :idle)
      end

      def saving
        render Admin::Ui::SaveStatusComponent.new(id: "save-status-saving", state: :saving)
      end

      def saved
        render Admin::Ui::SaveStatusComponent.new(id: "save-status-saved", state: :saved, at: Time.current)
      end

      def saved_live
        render Admin::Ui::SaveStatusComponent.new(id: "save-status-saved-live", state: :saved, at: Time.current, live: true)
      end

      def error
        render Admin::Ui::SaveStatusComponent.new(id: "save-status-error", state: :error, count: 2)
      end

      def retrying
        render Admin::Ui::SaveStatusComponent.new(id: "save-status-retrying", state: :retrying)
      end

      def offline
        render Admin::Ui::SaveStatusComponent.new(id: "save-status-offline", state: :offline)
      end

      def stale
        render Admin::Ui::SaveStatusComponent.new(id: "save-status-stale", state: :stale)
      end

      # Another tab of someone else's holds the record; with no holder handed
      # over, the line says only that it is held.
      def held
        render Admin::Ui::SaveStatusComponent.new(id: "save-status-held", state: :held)
      end

      def saved_over
        render Admin::Ui::SaveStatusComponent.new(id: "save-status-saved-over", state: :saved_over)
      end

      def signed_out
        render Admin::Ui::SaveStatusComponent.new(id: "save-status-signed-out", state: :signed_out)
      end

      def forbidden
        render Admin::Ui::SaveStatusComponent.new(id: "save-status-forbidden", state: :forbidden)
      end
    end
  end
end
