module Admin
  module Ui
    # `Admin::Ui::RecordChipComponent`: each kind's chip alone, and a chip
    # with its word, as a list's type column draws it.
    class RecordChipComponentPreview < ViewComponent::Preview
      def page = render(Admin::Ui::RecordChipComponent.new(kind: "page"))

      def post = render(Admin::Ui::RecordChipComponent.new(kind: "post"))

      def media = render(Admin::Ui::RecordChipComponent.new(kind: "media"))

      def form = render(Admin::Ui::RecordChipComponent.new(kind: "form"))

      def settings = render(Admin::Ui::RecordChipComponent.new(kind: "settings"))

      def labelled = render(Admin::Ui::RecordChipComponent.new(kind: "page", label: "Page"))
    end
  end
end
