module Admin
  module TranslationScreen
    # `Admin::TranslationScreen::OutdatedNoteComponent` (translation helpers
    # spec §4): the note with its "Mark as up to date" button, and the note
    # alone, as a view-only editor sees it.
    class OutdatedNoteComponentPreview < ViewComponent::Preview
      def confirmable
        render Admin::TranslationScreen::OutdatedNoteComponent.new(confirm: { record_type: "Page", record_id: 1, field: "title", locale: "de" })
      end

      def view_only
        render Admin::TranslationScreen::OutdatedNoteComponent.new
      end
    end
  end
end
