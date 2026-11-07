module Admin
  module Ui
    # `Admin::Ui::ButtonComponent`: the primary at rest, then one example per
    # other variant, the small size and the disabled look. Hover, focus and
    # the press are the browser's.
    class ButtonComponentPreview < ViewComponent::Preview
      def rest
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

      def tertiary
        render Admin::Ui::ButtonComponent.new(label: "Cancel", variant: :tertiary)
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
