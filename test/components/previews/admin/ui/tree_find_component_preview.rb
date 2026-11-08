module Admin
  module Ui
    # `Admin::Ui::TreeFindComponent` as the server draws it: an empty field
    # with its "/" hint. Focus is the browser's; what typing does (the
    # narrowed tree, its marks, the count and the no-match line) is the
    # script's, held by test/system/admin/tree_find_test.rb.
    class TreeFindComponentPreview < ViewComponent::Preview
      def rest
        render(Admin::Ui::TreeFindComponent.new(controls: "preview-tree", noun: :pages, moving: true))
      end
    end
  end
end
