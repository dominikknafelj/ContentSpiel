module Admin
  module Ui
    # The explicit-save bar for configuration screens (design pass spec §4,
    # handoff §9 B12): sticky at the foot of the form and always visible, with
    # Save, Cancel (which leaves without asking, `data-save-bar-cancel`) and a
    # live count of changed fields. It is rendered *inside* the form that carries `admin--saving--save-bar`
    # (the controller finds its `bar`/`count` targets by being an ancestor), and
    # its Save names the form with `form=` as well, so the button keeps working
    # if a layout change ever moves the bar out of the `<form>` element.
    #
    # `save_data:` is merged onto the Save button -- the account screen's
    # password form needs `data-password-submit` on it so the strength meter can
    # hold the submit back until the password is long enough.
    class SaveBarComponent < AdminComponent
      # `contained: true` is the footer of ONE card, drawn inside it (the notes
      # handoff's decision 34): under a line, within the card's padding, on the
      # card's own surface, and not stuck to the window -- the card is short
      # and its footer is where the card ends. Put it in the card as its last
      # part. The default is the footer of a whole form, unchanged.
      def initialize(form_id:, cancel_url:, save_label: nil, save_data: {}, contained: false)
        @form_id = form_id
        @contained = contained
        @cancel_url = cancel_url
        @save_label = save_label
        @save_data = save_data
      end

      private

      attr_reader :form_id, :cancel_url, :save_data

      # A default argument can't ask `t`: nothing is rendering yet at `initialize`.
      def save_label = @save_label || t(".save")

      def bar_class
        return "admin-save-bar admin-save-bar--contained flex flex-wrap items-center gap-3 border-t border-line px-[18px] py-3.5" if @contained

        "admin-save-bar sticky bottom-0 z-20 mt-6 flex flex-wrap items-center gap-3 border-t border-line bg-paper py-3"
      end
    end
  end
end
