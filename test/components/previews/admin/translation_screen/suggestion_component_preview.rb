module Admin
  module TranslationScreen
    # `Admin::TranslationScreen::SuggestionComponent`: an editable plain
    # suggestion naming its model, the same without a model name, and the
    # inline error.
    class SuggestionComponentPreview < ViewComponent::Preview
      def plain_with_model
        render Admin::TranslationScreen::SuggestionComponent.new(input_id: "post-title", locale: "de", suggestion: "Hallo Welt",
          model: "claude-sonnet-5")
      end

      def plain_without_model
        render Admin::TranslationScreen::SuggestionComponent.new(input_id: "post-title", locale: "de", suggestion: "Hallo Welt")
      end

      def with_repair_notes
        document = RichText::Document.from_markdown("Hallo **Welt**").first
        render Admin::TranslationScreen::SuggestionComponent.new(input_id: "post-body-json", locale: "de", suggestion: document, model: "claude-sonnet-5",
          warnings: [ "Unknown directive ::foo was kept as text", "An empty quote was removed" ])
      end

      # Suggest update: the full new text with the existing translation above it.
      def update_with_current
        render Admin::TranslationScreen::SuggestionComponent.new(input_id: "post-title", locale: "de", suggestion: "Über unser Team",
          model: "claude-sonnet-5", mode: :update, current: "Über uns")
      end

      def error
        render Admin::TranslationScreen::SuggestionComponent.new(input_id: "post-title", locale: "de", error: "The AI provider is unavailable.")
      end
    end
  end
end
