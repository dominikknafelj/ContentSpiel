module Admin
  module Ui
    # The "or" between one way in and the next: a rule, the word, a rule, in
    # the meta words of a panel's small type. Drawn on the sign-in panel
    # (between the password form and the ways in below it), in Confirm it's
    # you (between the passkey and the password) and on the invitation page.
    #
    # DECORATION, hidden from a screen reader as a whole (`aria-hidden`): the
    # ways in on both sides are buttons and fields named by their own words
    # ("Sign in with a passkey", "Password"), so a person who hears them
    # needs no "or" between them, and a separator read as "or" between two
    # named controls would be read as content of neither.
    #
    # `hidden:` draws it hidden, for a script that shows it with what it
    # stands for (`passkey-sign-in`, which shows its divider once the
    # browser can use a passkey). Anything else the caller needs on the tag
    # (`data` for a script's target) passes through.
    class OrDividerComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Decoration hidden from a screen reader as a whole, with no focus: the ways in on both sides are named by their own words.",
        motion: :none,
        content_edges: %i[short],
        widths: :from_container,
        interface: %i[hidden],
        limits: [
          "It draws one word between two rules and nothing else: a caller's words go in the controls around it.",
          "A script that shows it is the caller's: it is drawn hidden or not, and changes nothing itself."
        ],
        states: %i[rest hidden],
        keys: %w[or],
        slots: [],
        controller: nil,
        keyboard: "It takes no focus: decoration hidden from a screen reader between two ways in, each a control of its own."
      )

      CLASS = "flex items-center gap-3 text-small text-meta".freeze

      def initialize(hidden: false, **html)
        @hidden = hidden
        @html = html
      end

      def call
        tag.div(class: CLASS, hidden: @hidden, aria: { hidden: true }, **@html) do
          safe_join([ rule, tag.span(t(".or")), rule ])
        end
      end

      private

      def rule = tag.span(class: "h-px flex-1 bg-line")
    end
  end
end
