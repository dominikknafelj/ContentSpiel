module Admin
  module TranslationScreen
    # `Admin::TranslationScreen::PendingComponent`: the running state. The
    # 25-second state is in the markup too, hidden (`admin--translate` flips
    # it); the preview shows it by itself.
    class PendingComponentPreview < ViewComponent::Preview
      def running
        render Admin::TranslationScreen::PendingComponent.new
      end
    end
  end
end
