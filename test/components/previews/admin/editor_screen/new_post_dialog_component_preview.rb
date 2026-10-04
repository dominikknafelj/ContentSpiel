module Admin
  module EditorScreen
    # `Admin::EditorScreen::NewPostDialogComponent`: closed to start with, like
    # the New page dialog's preview. `form` is the form alone; `with_error` is a
    # refused create's replacement form.
    class NewPostDialogComponentPreview < ViewComponent::Preview
      def default
        render Admin::EditorScreen::NewPostDialogComponent.new
      end

      def form
        render Admin::EditorScreen::NewPostFormComponent.new
      end

      def with_error
        post = Post.new
        post.errors.add(:title, "can't be blank")
        render Admin::EditorScreen::NewPostFormComponent.new(content_type: "now_update", errors: post.errors)
      end
    end
  end
end
