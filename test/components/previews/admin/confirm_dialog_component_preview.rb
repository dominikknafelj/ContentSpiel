module Admin
  # `Admin::ConfirmDialogComponent` (cs-studio spec §5.1/§5.3): rendered
  # `[open]` for the preview, since Lookbook has no trigger button to call
  # `showModal()` for it.
  class ConfirmDialogComponentPreview < ViewComponent::Preview
    def delete_page
      render(Admin::ConfirmDialogComponent.new(id: "delete-page-preview", title: "Delete this page?", body: "This can't be undone.")) do |component|
        component.with_confirm_action { render(Admin::ButtonComponent.new(label: "Delete", variant: :danger, type: "submit")) }
      end
    end

    def rename_tag_without_confirm_action
      render Admin::ConfirmDialogComponent.new(id: "rename-tag-preview", title: "Rename tag \"blog\"?")
    end
  end
end
