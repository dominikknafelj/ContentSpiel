module Admin
  module Ui
    # `Admin::Ui::ThemeSwitchComponent` at rest; which choice is marked is
    # the `theme` controller's.
    class ThemeSwitchComponentPreview < ViewComponent::Preview
      def rest = render(Admin::Ui::ThemeSwitchComponent.new)
    end
  end
end
