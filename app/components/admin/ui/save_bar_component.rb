module Admin
  module Ui
    # The explicit-save bar for configuration screens: sticky at the foot of the form and always visible, with
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
      include Admin::Ui::Contract

      contract(
        accessibility: "A Save button and a Cancel link, with a polite live region for the count of changes and a status for the blocked hint.",
        motion: :reduced,
        content_edges: %i[short],
        widths: :from_container,
        interface: %i[form_id cancel_url save_label save_data contained],
        limits: [
          "The count, the blocked hint and Save's disabled state are written by admin--saving--save-bar on the form; without JavaScript Save is a plain working submit.",
          "It must stand inside the form that carries admin--saving--save-bar.",
          "Its parts are targets of admin--saving--save-bar, which the form around it attaches."
        ],
        states: %i[rest contained hover focus],
        script_states: {
          changed: [ "test/system/save_bar_test.rb", "the footer is always there, counts changes, disables Save when nothing changed, and guards leaving" ],
          stuck: [ "test/system/save_bar_test.rb", "a footer stuck over the fields draws a stronger top edge and an elevation, and at the end of the form neither" ],
          blocked: [ "test/system/save_bar_test.rb", "Change password is locked while the name is unsaved, and unlocks when it is saved" ]
        },
        keys: %w[save cancel changes unsaved no_changes blocked],
        slots: [],
        controller: nil
      )

      # `contained: true` is the footer of ONE card, drawn inside it: under a line, within the card's padding, on the
      # card's own surface, and not stuck to the window -- the card is short
      # and its footer is where the card ends. Put it in the card as its last
      # part. The default is the footer of a whole form.
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

      # `-bottom-px`: the bar sticks one pixel below the window's edge, so a
      # bar that sticks is never wholly inside the window and the
      # controller's IntersectionObserver (threshold 1) can tell stuck from
      # at rest.
      def bar_class
        return "admin-save-bar admin-save-bar--contained flex flex-wrap items-center gap-3 border-t border-line px-[18px] py-3.5" if @contained

        "admin-save-bar sticky -bottom-px z-(--cs-z-sticky) mt-6 flex flex-wrap items-center gap-3 border-t border-line bg-paper py-3"
      end
    end
  end
end
