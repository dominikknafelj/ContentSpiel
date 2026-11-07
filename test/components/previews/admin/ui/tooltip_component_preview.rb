module Admin
  module Ui
    # `Admin::Ui::TooltipComponent` on its host, an icon button
    # (`ButtonComponent`'s `icon:`). The bubble is drawn hidden, so this shows
    # the host only: showing it on hover and on focus is `admin--ui--tooltip`'s,
    # which a CS Studio screen runs and Lookbook's layout does not. Its look is
    # held by the browser test its contract names.
    class TooltipComponentPreview < ViewComponent::Preview
      def on_an_icon_button
        render Admin::Ui::ButtonComponent.new(label: "Close", variant: :tertiary, size: :small, icon: :x)
      end
    end
  end
end
