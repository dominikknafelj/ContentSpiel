module Admin
  module Ui
    # A switched-off type, named by a name no type declares so the example
    # needs no site settings, and a switched-on one (which draws nothing).
    class TypeStateComponentPreview < ViewComponent::Preview
      def switched_off = render(Admin::Ui::TypeStateComponent.new(content_type: "retired_type"))

      def switched_on = render(Admin::Ui::TypeStateComponent.new(content_type: ::ContentTypes.default.name))
    end
  end
end
