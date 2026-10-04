module Admin
  module TrashScreen
    # `EmptyTrashComponent` (round 3, Task 14): the header button and its
    # dialog (click the button to open it), sentence per mix of kinds.
    class EmptyTrashComponentPreview < ViewComponent::Preview
      def all_kinds = render(Admin::TrashScreen::EmptyTrashComponent.new(pages: 1, subpages: 1, posts: 1, images: 1))
      def posts_only = render(Admin::TrashScreen::EmptyTrashComponent.new(pages: 0, subpages: 0, posts: 3, images: 0))
    end
  end
end
