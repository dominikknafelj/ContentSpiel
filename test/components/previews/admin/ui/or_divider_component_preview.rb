module Admin
  module Ui
    # `Admin::Ui::OrDividerComponent`: the "or" as a panel draws it, and the
    # hidden one a script shows with what it stands for.
    class OrDividerComponentPreview < ViewComponent::Preview
      def rest
        render Admin::Ui::OrDividerComponent.new
      end

      def hidden
        render Admin::Ui::OrDividerComponent.new(hidden: true)
      end
    end
  end
end
