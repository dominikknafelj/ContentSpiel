module Admin
  module TranslationScreen
    # `Admin::TranslationScreen::TranslateAllComponent`: the header's idle
    # state. It needs AI set up and `ai.translate`, and counts the empty fields
    # of a real record, so the preview renders nothing until a post with an
    # untranslated field exists and AI is configured in Settings.
    class TranslateAllComponentPreview < ViewComponent::Preview
      def idle
        post = Post.kept.first
        render Admin::TranslationScreen::TranslateAllComponent.new(record: post || Post.new, locale: Translations.target_locales.first || "de", editable: true)
      end
    end
  end
end
