module Admin
  module Ui
    class ThemeSwitchComponentPreview < ViewComponent::Preview
      def default = render(Admin::Ui::ThemeSwitchComponent.new)
    end
  end
end
