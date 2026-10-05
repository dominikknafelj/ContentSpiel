module Admin
  # `Admin::DialogComponent` at each width step (the footer slot carries the
  # actions). The dialogs are closed until a trigger opens them, so each
  # preview renders its own `dialog_trigger` button -- Lookbook's layout has
  # no `<body data-controller="admin--dialog">`, so open them from the
  # browser console with `document.getElementById(id).showModal()`.
  class DialogComponentPreview < ViewComponent::Preview
    def form
      render(Admin::DialogComponent.new(id: "dialog-preview-form", title: "New post", width: :form)) do |dialog|
        dialog.with_footer { render(Admin::ButtonComponent.new(label: "Create", type: "submit")) }
        "A form would go here."
      end
    end

    def form_narrow
      render(Admin::DialogComponent.new(id: "dialog-preview-narrow", title: "Rename tag", width: :form_narrow)) { "A short form." }
    end

    # `hang: true`: the dialog hangs from a fixed top edge instead of being
    # centred, for one whose height changes while it is open (New page, New
    # post) -- so its header and buttons stay where they were when the content
    # arrives. Open it, then change the body's height in the inspector: the top
    # edge doesn't move.
    def hanging
      render(Admin::DialogComponent.new(id: "dialog-preview-hang", title: "New page", width: :form, hang: true)) do |dialog|
        dialog.with_footer { render(Admin::ButtonComponent.new(label: "Create", type: "submit")) }
        "Loading…"
      end
    end
  end
end
