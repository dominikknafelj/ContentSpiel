module Admin
  module EditorScreen
    # `Admin::EditorScreen::NewPostDialogComponent`: closed to start with, like
    # the New page dialog's preview. `form` is the form alone; `with_error` is a
    # refused create's replacement form; `one_type` is the form of a viewer who
    # may create one type only, with no Type select.
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

      # A user in one group that may create `now_update` posts alone. The rows
      # are the preview request's (`ComponentPreviewsController` discards
      # them), and `Current` is set for the rest of the request: a preview
      # renders after its method returns, so a `Current.set` block would
      # already be over.
      def one_type
        group = AccessControl::Group.create!(name: "Preview: now updates #{SecureRandom.hex(4)}")
        AccessControl::Grant.create!(group: group, permission: "posts.create", scope: { "content_types" => [ "now_update" ] })
        user = User.create!(email_address: "new-post-preview-#{SecureRandom.hex(4)}@example.com", password: "password12345")
        user.groups << group
        Current.actor = user
        Current.channel = :admin
        render Admin::EditorScreen::NewPostFormComponent.new
      end
    end
  end
end
