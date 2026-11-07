module Admin
  module Ui
    # `Admin::Ui::PrefixInputComponent`: at rest and invalid.
    class PrefixInputComponentPreview < ViewComponent::Preview
      def rest
        render Admin::Ui::PrefixInputComponent.new(name: "slug", id: "slug", value: "about", prefix: "example.com/de/")
      end

      def invalid
        render Admin::Ui::PrefixInputComponent.new(name: "slug", id: "slug", value: "", prefix: "example.com/", errors: [ "can't be blank" ])
      end
    end
  end
end
