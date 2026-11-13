module Admin
  module Ui
    # `Admin::Ui::WayInButtonComponent`: its three looks, with the provider's
    # words. The address is nowhere: a preview's press goes nowhere useful.
    class WayInButtonComponentPreview < ViewComponent::Preview
      def secondary
        render Admin::Ui::WayInButtonComponent.new(label: "Sign in with Okta", url: "#")
      end

      def primary
        render Admin::Ui::WayInButtonComponent.new(label: "Sign in with Okta", url: "#", variant: :primary)
      end

      def tertiary
        render Admin::Ui::WayInButtonComponent.new(label: "Sign in with Okta instead", url: "#", variant: :tertiary)
      end
    end
  end
end
