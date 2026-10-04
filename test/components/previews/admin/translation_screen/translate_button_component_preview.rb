module Admin
  module TranslationScreen
    # `Admin::TranslationScreen::TranslateButtonComponent`: the button under a
    # translated field's input. It renders nothing unless AI is set up in
    # Settings and the viewer holds `ai.translate`; `update` is the outdated
    # reference card's "Suggest update" variant.
    class TranslateButtonComponentPreview < ViewComponent::Preview
      CONFIRM = { record_type: "Post", record_id: 0, field: "title", locale: "de" }.freeze

      def translate
        render Admin::TranslationScreen::TranslateButtonComponent.new(confirm: CONFIRM, input_id: "post-title", characters: 24)
      end

      def update
        render Admin::TranslationScreen::TranslateButtonComponent.new(confirm: CONFIRM, input_id: "post-title", characters: 24, mode: :update)
      end
    end
  end
end
