module Admin
  module DashboardScreen
    class QuickCreateComponentPreview < ViewComponent::Preview
      def default
        render Admin::DashboardScreen::QuickCreateComponent.new
      end

      def with_error
        render Admin::DashboardScreen::QuickCreateComponent.new(title: "", errors: [ "Title can't be blank" ])
      end
    end
  end
end
