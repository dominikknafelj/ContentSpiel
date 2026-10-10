module Admin
  module Ui
    # `Admin::Ui::ButtonComponent` (cs-studio spec §4.3): one example per variant.
    class ButtonComponentPreview < ViewComponent::Preview
      def primary
        render Admin::Ui::ButtonComponent.new(label: "Save page")
      end

      def secondary
        render Admin::Ui::ButtonComponent.new(label: "Cancel", variant: :secondary)
      end

      def danger
        render Admin::Ui::ButtonComponent.new(label: "Delete page", variant: :danger)
      end

      def danger_text
        render Admin::Ui::ButtonComponent.new(label: "Move to trash", variant: :danger_text)
      end

      def ghost
        render Admin::Ui::ButtonComponent.new(label: "Cancel", variant: :ghost)
      end

      def small
        render Admin::Ui::ButtonComponent.new(label: "Use", size: :small)
      end

      def disabled
        render Admin::Ui::ButtonComponent.new(label: "Saving…", disabled: true)
      end
    end
  end
end
