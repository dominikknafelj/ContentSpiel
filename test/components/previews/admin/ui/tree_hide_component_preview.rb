module Admin
  module Ui
    # `Admin::Ui::TreeHideComponent` as the server draws it, expanded, in the
    # Pages tree's words. Hover and focus are the browser's; the folded
    # column it leads to is the script's, held by
    # test/system/admin/tree_fold_test.rb.
    class TreeHideComponentPreview < ViewComponent::Preview
      def rest
        render(Admin::Ui::TreeHideComponent.new(subject: "pages"))
      end
    end
  end
end
