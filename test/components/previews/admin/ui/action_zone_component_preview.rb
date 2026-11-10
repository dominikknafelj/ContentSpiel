module Admin
  module Ui
    # `Admin::Ui::ActionZoneComponent`, an instant action after a form: at
    # rest, with the reason it can't be taken, and waiting for the form above
    # it (the hint stays hidden until a form on the page has unsaved changes).
    class ActionZoneComponentPreview < ViewComponent::Preview
      def rest = render_with_template

      def reason = render_with_template

      def locked = render_with_template
    end
  end
end
