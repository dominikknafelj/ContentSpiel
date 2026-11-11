module Admin
  module EditorScreen
    # The New page dialog's form (its shell is
    # `Admin::Ui::NewRecordDialogComponentPreview`): `form` shows the form
    # alone, as the no-JS page renders it; `with_error` is a refused create's
    # replacement form.
    class NewPageFormComponentPreview < ViewComponent::Preview
      def form
        PreviewFixtures.page(title: "About")
        render Admin::EditorScreen::NewPageFormComponent.new
      end

      def with_error
        page = Page.new
        page.errors.add(:title, "can't be blank")
        render Admin::EditorScreen::NewPageFormComponent.new(template: "landing", errors: page.errors)
      end
    end
  end
end
