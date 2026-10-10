module Admin
  module EditorScreen
    # `Admin::EditorScreen::NewPageDialogComponent`: the dialog starts closed
    # (Lookbook's layout has no `admin--ui--dialog` on `<body>`), so open it from the
    # console with `document.querySelector("dialog").showModal()`. `form` shows
    # the form alone, as the no-JS page renders it; `with_error` is a refused
    # create's replacement form.
    class NewPageDialogComponentPreview < ViewComponent::Preview
      def default
        PreviewFixtures.page(title: "About")
        render Admin::EditorScreen::NewPageDialogComponent.new
      end

      def form
        render Admin::EditorScreen::NewPageFormComponent.new
      end

      def with_error
        page = Page.new
        page.errors.add(:title, "can't be blank")
        render Admin::EditorScreen::NewPageFormComponent.new(page_type: "landing", errors: page.errors)
      end
    end
  end
end
