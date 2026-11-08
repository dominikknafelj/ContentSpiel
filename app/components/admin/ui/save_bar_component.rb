module Admin
  module Ui
    # The explicit-save bar for configuration screens. By default it floats
    # at the foot of the form's column at elevation 3 (the popover's ground,
    # a card's radius), sticky over the fields while a long form scrolls: an
    # 8px accent dot while something is unsaved, the count with the names of
    # what changed, then Discard (which leaves without asking,
    # `data-save-bar-cancel`) and Save at the end. It is rendered *inside* the
    # form that carries `admin--saving--save-bar` (the controller finds its
    # targets by being an ancestor), and its Save names the form with
    # `form=` as well, so the button keeps working if a layout change ever
    # moves the bar out of the `<form>` element.
    #
    # `save_data:` is merged onto the Save button -- the account screen's
    # password form needs `data-password-submit` on it so the strength meter can
    # hold the submit back until the password is long enough.
    class SaveBarComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A Save button and a Discard link, with a polite live region for the count and the names of the changes, a hidden dot beside it, and a status for the blocked hint.",
        motion: :reduced,
        content_edges: %i[short],
        widths: :from_container,
        interface: %i[form_id cancel_url save_label save_data contained],
        limits: [
          "The count, the names, the dot, the blocked hint and Save's disabled state are written by admin--saving--save-bar on the form; without JavaScript Save is a plain working submit.",
          "It names at most three changed fields, then how many more; a field it cannot name is counted and not named.",
          "It must stand inside the form that carries admin--saving--save-bar.",
          "Its parts are targets of admin--saving--save-bar, which the form around it attaches."
        ],
        states: %i[rest contained hover focus],
        script_states: {
          changed: [ "test/system/save_bar_test.rb", "the footer is always there, counts changes, disables Save when nothing changed, and guards leaving" ],
          named: [ "test/system/save_bar_test.rb", "the bar names up to three changed fields and how many more" ],
          marked: [ "test/system/save_bar_test.rb", "a changed field carries the mark, and loses it when typed back" ],
          blocked: [ "test/system/save_bar_test.rb", "Change password is locked while the name is unsaved, and unlocks when it is saved" ]
        },
        keys: %w[save_changes discard changes names more separator per_language order_changed unsaved no_changes blocked],
        slots: [],
        controller: nil
      )

      # `contained: true` is the footer of ONE card, drawn inside it: under a
      # line, within the card's padding, on the card's own surface, not stuck to
      # the window and with no dot -- the card is short and its footer is where
      # the card ends. Put it in the card as its last part. The default is the
      # floating bar of a whole form.
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
      def save_label = @save_label || t(".save_changes")

      def contained? = @contained

      # Sticky at `--cs-sp-3` above the window's edge, so the bar floats clear
      # of it over the fields and stands under them at the form's end.
      def bar_class
        return "admin-save-bar admin-save-bar--contained flex flex-wrap items-center gap-3 border-t border-line px-[18px] py-3.5" if contained?

        "admin-save-bar admin-save-bar--floating sticky bottom-(--cs-sp-3) z-(--cs-z-sticky) mt-6 flex flex-wrap items-center gap-3 rounded-card bg-popover px-4 py-3 shadow-3"
      end
    end
  end
end
