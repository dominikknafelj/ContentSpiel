module Admin
  module Ui
    # `Admin::Ui::PrefixInputComponent` (design pass spec §4): plain and invalid.
    class PrefixInputComponentPreview < ViewComponent::Preview
      def plain
        render Admin::Ui::PrefixInputComponent.new(name: "slug", id: "slug", value: "about", prefix: "example.com/de/")
      end

      def with_error
        render Admin::Ui::PrefixInputComponent.new(name: "slug", id: "slug", value: "", prefix: "example.com/", errors: [ "can't be blank" ])
      end
    end
  end
end
