module Admin
  module EditorScreen
    # The rich-text editor's three shared dialogs, closed. Lookbook's layout has no
    # `<body data-controller="admin--ui--dialog">`; open one from the console with
    # `document.getElementById("rich-text-image-dialog").showModal()`.
    class RichTextDialogsComponentPreview < ViewComponent::Preview
      def default
        render(Admin::EditorScreen::RichTextDialogsComponent.new)
      end
    end
  end
end
