module Admin
  # The explicit-save bar for configuration screens (design pass spec §4,
  # handoff §9 B12): sticky at the foot of the form and always visible, with
  # Save, Cancel (which leaves without asking, `data-save-bar-cancel`) and a
  # live count of changed fields. It is rendered *inside* the form that carries `admin--save-bar`
  # (the controller finds its `bar`/`count` targets by being an ancestor), and
  # its Save names the form with `form=` as well, so the button keeps working
  # if a layout change ever moves the bar out of the `<form>` element.
  #
  # `save_data:` is merged onto the Save button -- the account screen's
  # password form needs `data-password-submit` on it so the strength meter can
  # hold the submit back until the password is long enough.
  class SaveBarComponent < AdminComponent
    def initialize(form_id:, cancel_url:, save_label: nil, save_data: {})
      @form_id = form_id
      @cancel_url = cancel_url
      @save_label = save_label
      @save_data = save_data
    end

    private

    attr_reader :form_id, :cancel_url, :save_data

    # A default argument can't ask `t`: nothing is rendering yet at `initialize`.
    def save_label = @save_label || t(".save")
  end
end
