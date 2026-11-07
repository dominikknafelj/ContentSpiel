module Admin
  module Ui
    # `Admin::Ui::ConfirmDialogComponent`. `rest` and `destructive` are marked
    # `open_on_load`, so `admin--ui--dialog` opens them as the page appears
    # where the admin's script runs; the others are closed until a trigger
    # opens them (`document.getElementById(id).showModal()` in the console).
    class ConfirmDialogComponentPreview < ViewComponent::Preview
      def rest
        render(Admin::Ui::ConfirmDialogComponent.new(id: "turn-off-preview", title: "Turn off Deutsch?", open_on_load: true,
          body: "Its translations are kept, and come back when it is turned on again.")) do |component|
          component.with_confirm_action { render(Admin::Ui::ButtonComponent.new(label: "Turn off", type: "submit")) }
        end
      end

      def destructive
        render(Admin::Ui::ConfirmDialogComponent.new(id: "delete-page-preview", title: "Delete this page?", body: "This can't be undone.", destructive: true,
          open_on_load: true)) do |component|
          component.with_confirm_action { render(Admin::Ui::ButtonComponent.new(label: "Delete", variant: :danger, type: "submit")) }
        end
      end

      # A confirmation that lists what it affects (deleting a group names the
      # tokens it revokes).
      def delete_group_with_details
        render(Admin::Ui::ConfirmDialogComponent.new(id: "delete-group-preview", title: "Delete the group “Bots”?", destructive: true,
          body: "Deleting it revokes 2 tokens. This can't be undone.")) do |component|
          component.with_details { "Claude desktop — ada@example.com, Nightly import — grace@example.com" }
          component.with_confirm_action { render(Admin::Ui::ButtonComponent.new(label: "Delete", variant: :danger, type: "submit")) }
        end
      end

      def rename_tag_without_confirm_action
        render Admin::Ui::ConfirmDialogComponent.new(id: "rename-tag-preview", title: "Rename tag \"blog\"?")
      end
    end
  end
end
