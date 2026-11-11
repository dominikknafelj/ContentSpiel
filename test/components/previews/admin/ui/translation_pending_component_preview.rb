module Admin
  module Ui
    # `Admin::Ui::TranslationPendingComponent`: the running state. The
    # 25-second state is in the markup too, hidden (`admin--translation--translate` flips
    # it); the preview shows it by itself.
    class TranslationPendingComponentPreview < ViewComponent::Preview
      def running
        render Admin::Ui::TranslationPendingComponent.new
      end
    end
  end
end
