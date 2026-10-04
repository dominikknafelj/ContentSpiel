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

      def error
        render Admin::TranslationScreen::SuggestionComponent.new(input_id: "post-title", locale: "de", error: "The AI provider is unavailable.")
      end
    end
  end
end
