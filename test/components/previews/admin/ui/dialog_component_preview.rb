module Admin
  module Ui
    # `Admin::Ui::DialogComponent` at rest and at each width step (the footer
    # slot carries the actions). `rest` is marked `open_on_load`, so
    # `admin--ui--dialog` opens it as the page appears where the admin's
    # script runs; the others are closed until a trigger opens them. Lookbook's
    # layout has no `<body data-controller="admin--ui--dialog">`, so open them
    # there from the browser console with `document.getElementById(id).showModal()`.
    class DialogComponentPreview < ViewComponent::Preview
      def rest
        render(Admin::Ui::DialogComponent.new(id: "dialog-preview-rest", title: "Rename tag", open_on_load: true)) do |dialog|
          dialog.with_footer { render(Admin::Ui::ButtonComponent.new(label: "Rename", type: "submit")) }
          "A short form."
        end
      end

      def form
        render(Admin::Ui::DialogComponent.new(id: "dialog-preview-form", title: "New post", width: :form)) do |dialog|
          dialog.with_footer { render(Admin::Ui::ButtonComponent.new(label: "Create", type: "submit")) }
          "A form would go here."
        end
      end

      def form_narrow
        render(Admin::Ui::DialogComponent.new(id: "dialog-preview-narrow", title: "Rename tag", width: :form_narrow)) { "A short form." }
      end

      # `hang: true`: the dialog hangs from a fixed top edge instead of being
      # centred, for one whose height changes while it is open (New page, New
      # post) -- so its header and buttons stay where they were when the content
      # arrives. Open it, then change the body's height in the inspector: the top
      # edge doesn't move.
      def hanging
        render(Admin::Ui::DialogComponent.new(id: "dialog-preview-hang", title: "New page", width: :form, hang: true)) do |dialog|
          dialog.with_footer { render(Admin::Ui::ButtonComponent.new(label: "Create", type: "submit")) }
          "Loading…"
        end
      end
    end
  end
end
