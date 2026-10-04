module Admin
  module SaveBarHelper
  # The `data:` a form carries to be driven by `admin--save-bar`
  # (`Admin::SaveBarComponent`): the controller plus the actions it listens
  # for. One definition, so the explicit-save screens can't drift.
  #
  # `dirty:` -- the server re-rendered this form with errors (a 422). The
  # re-render replaces the form, so the controller reconnects and snapshots
  # the typed, invalid values as its baseline: without this it would count 0
  # changes, disable the only Save button and leave the edits unguarded.
  # While `dirty` Save stays enabled and leaving asks first, whatever the
  # snapshot says.
  #
  # `always:` -- Save is enabled even with nothing changed. For a form that
  # is there to be submitted (a new record): Save must be pressable before
  # any typing. The leave guard still waits for a real change.
  def save_bar_form_data(dirty: false, always: false)
    {
      controller: "admin--save-bar",
      "admin--save-bar-dirty-value": dirty,
      "admin--save-bar-always-value": always,
      action: "input->admin--save-bar#refresh change->admin--save-bar#refresh turbo:submit-start->admin--save-bar#markSubmitting turbo:submit-end->admin--save-bar#submitEnded"
    }
  end
  end
end
