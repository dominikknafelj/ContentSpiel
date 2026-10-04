module Admin
  # The `data:` a form carries to be driven by `admin--save-bar`
  # (`Admin::SaveBarComponent`): the controller plus the three actions it
  # listens for. One definition, so the explicit-save screens can't drift.
  module SaveBarHelper
    def save_bar_form_data
      {
        controller: "admin--save-bar",
        action: "input->admin--save-bar#refresh change->admin--save-bar#refresh turbo:submit-start->admin--save-bar#markSubmitting"
      }
    end
  end
end
