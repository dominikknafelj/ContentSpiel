module Admin
  # `Admin::ConfirmDialogComponent` (cs-studio spec §5.1/§5.3): rendered
  # `[open]` for the preview, since Lookbook has no trigger button to call
  # `showModal()` for it.
  class ConfirmDialogComponentPreview < ViewComponent::Preview
    def delete_page
      render(Admin::ConfirmDialogComponent.new(id: "delete-page-preview", title: "Delete this page?", body: "This can't be undone.", destructive: true)) do |component|
        component.with_confirm_action { render(Admin::ButtonComponent.new(label: "Delete", variant: :danger, type: "submit")) }
      end
    end

    # A confirmation that lists what it affects (deleting a group names the
    # tokens it revokes).
    def delete_group_with_details
      render(Admin::ConfirmDialogComponent.new(id: "delete-group-preview", title: "Delete the group “Bots”?", destructive: true,
        body: "Deleting it revokes 2 tokens. This can't be undone.")) do |component|
        component.with_details { "API token #3 — ada@example.com, API token #7 — grace@example.com" }
        component.with_confirm_action { render(Admin::ButtonComponent.new(label: "Delete", variant: :danger, type: "submit")) }
      end
    end

    def rename_tag_without_confirm_action
      render Admin::ConfirmDialogComponent.new(id: "rename-tag-preview", title: "Rename tag \"blog\"?")
    end
  end
end
