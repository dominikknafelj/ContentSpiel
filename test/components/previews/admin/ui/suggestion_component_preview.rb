module Admin
  module Ui
    # `Admin::Ui::SuggestionComponent`: an editable plain suggestion naming its
    # model, a rich one with repair notes, an update beside the current
    # translation, and the inline error.
    class SuggestionComponentPreview < ViewComponent::Preview
      def plain
        render Admin::Ui::SuggestionComponent.new(input_id: "post-title", locale: "de", suggestion: "Hallo Welt",
          model: "claude-sonnet-5")
      end

      def rich
        document = RichText::Document.from_markdown("Hallo **Welt**").first
        render Admin::Ui::SuggestionComponent.new(input_id: "post-body-json", locale: "de", suggestion: document, model: "claude-sonnet-5",
          warnings: [ "Unknown directive ::foo was kept as text", "An empty quote was removed" ])
      end

      # Suggest update: the full new text with the existing translation above it.
      def update
        render Admin::Ui::SuggestionComponent.new(input_id: "post-title", locale: "de", suggestion: "Über unser Team",
          model: "claude-sonnet-5", mode: :update, current: "Über uns")
      end

      def error
        render Admin::Ui::SuggestionComponent.new(input_id: "post-title", locale: "de", error: "The AI provider is unavailable.")
      end
    end
  end
end
