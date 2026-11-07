module Admin
  module Ui
    # `Admin::Ui::SaveBarComponent`. The footer is always there;
    # `admin--saving--save-bar` writes its count and enables Save, so each
    # example wraps it in the controller with one field: type in it to see
    # both change. `rest` is a form's footer, `contained` the footer of one
    # card, under a line inside it.
    class SaveBarComponentPreview < ViewComponent::Preview
      def rest
        render_with_template
      end

      def contained
        render_with_template
      end
    end
  end
end
