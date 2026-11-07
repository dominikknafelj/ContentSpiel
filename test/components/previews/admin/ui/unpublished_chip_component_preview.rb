module Admin
  module Ui
    # `Admin::Ui::UnpublishedChipComponent`: the one chip, beside a title as
    # the editor's header and the posts list draw it.
    class UnpublishedChipComponentPreview < ViewComponent::Preview
      def rest = render(Admin::Ui::UnpublishedChipComponent.new)
    end
  end
end
