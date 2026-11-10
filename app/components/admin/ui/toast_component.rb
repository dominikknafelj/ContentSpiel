module Admin
  module Ui
    # One toast: a transient message at the foot of the screen. `kind` picks
    # the live-region role and how long it stays:
    #
    #   success  role=status  4 s
    #   undo     role=status  8 s  (a trash move, with its Undo `action`)
    #   warning  role=alert   until dismissed
    #   error    role=alert   until dismissed
    #
    # A failure never auto-hides: it is the one thing the editor must not miss
    # because they looked away for five seconds. The clock itself is
    # `admin--ui--toast` (it pauses on hover and focus, so an Undo can't vanish
    # under the pointer).
    #
    # `action` is `{ label:, url:, method: :post }` -- a `button_to`, never a
    # link, because every follow-up it exists for is a write (a restore is a
    # POST) and a GET link would be one prefetch away from performing it. Keys
    # may be strings: `flash[:undo]` comes back from the session JSON-encoded.
    # The message is a plain String and stays auto-escaped; a toast that needs
    # a link carries it as `action`, never as `html_safe` markup in the message.
    #
    # `id` is optional and only for a toast that has to be found again: the
    # autosave error toast (`Admin::AutosaveResponses`) never auto-hides, so the
    # form it belongs to gives it a stable id, replaces it on the next failure
    # and removes it on the next successful save. Without one, no `id` attribute
    # is rendered at all.
    #
    # A toast never comes back from Turbo's page cache (coming Back to a
    # screen must not show a stale Undo, or an error that has since been
    # fixed). `admin--ui--toast` sees to that, and its comment says why this
    # element must NOT carry `data-turbo-temporary` to get there: Turbo would
    # delete a live, just-relayed toast on the next frame navigation.
    class ToastComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A status (success, undo) or an alert (warning, error) with a Dismiss button and its action, when it has one, as a button.",
        motion: :none,
        content_edges: %i[short long],
        widths: :fluid,
        interface: %i[message kind action id],
        limits: [
          "A warning or an error never hides by itself; the clock and the pause on hover and focus are admin--ui--toast's.",
          "Its message is plain text: a link goes in its action, never in the message."
        ],
        states: %i[success undo warning error hover focus],
        keys: %w[dismiss save_failed order_failed dropped],
        slots: [],
        controller: "admin--ui--toast",
        keyboard: [ "test/system/admin/keyboard_feedback_test.rb", "a toast's action and its Dismiss are Tab stops after its words: Enter on Undo undoes, and Enter on Dismiss closes it" ]
      )

      KINDS = %i[success undo warning error].freeze
      TIMEOUTS = { success: 4000, undo: 8000, warning: 0, error: 0 }.freeze

      def initialize(message:, kind: :success, action: nil, id: nil)
        raise ArgumentError, "unknown toast kind #{kind.inspect}" unless KINDS.include?(kind.to_sym)

        @message = message
        @kind = kind.to_sym
        @action = action&.to_h&.with_indifferent_access
        @id = id.presence
      end

      def render? = message.present?

      private

      attr_reader :message, :kind, :action, :id

      def role = %i[warning error].include?(kind) ? "alert" : "status"

      def timeout = TIMEOUTS.fetch(kind)

      def action_method = action.fetch(:method, :post)
    end
  end
end
