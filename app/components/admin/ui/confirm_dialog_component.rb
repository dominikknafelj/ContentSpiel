module Admin
  module Ui
    # A native `<dialog>` for confirming a destructive action -- deleting a
    # page or post, renaming/deleting a tag that's in use,
    # unpublishing -- opened by whatever triggered it (a
    # `Ui::ButtonComponent` elsewhere on the page carrying
    # `data: dialog_trigger(id)`, wired at the call site since that's the only
    # place that knows *when* confirmation is needed). It is an
    # `Admin::Ui::DialogComponent` (confirm width) plus Cancel and the confirm
    # slot. A `destructive:` one puts initial focus on Cancel (`autofocus`),
    # so Enter never deletes by reflex; the confirm button should then be
    # `variant: :danger`.
    #
    # Cancelling needs no JavaScript at all: a `<form method="dialog">`'s
    # submit closes the nearest open `<dialog>` per the HTML spec, so the
    # Cancel button is a plain, unwired `<button>`. The actual confirm
    # action is a slot (`confirm_action`), not a `url:`/`method:` pair, so the
    # caller can render whatever it already uses to perform the write --
    # typically a `button_to` against a `Trash::Move`/`Tags::Destroy`-backed
    # route -- rather than this component reinventing Rails' own form helpers
    # for one method call.
    class ConfirmDialogComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "The shared dialog (a native modal named by its title, Escape closes it) with a Cancel button and the caller's confirm; a destructive one puts the focus on Cancel.",
        motion: :reduced,
        content_edges: %i[short long],
        widths: :fixed_width,
        interface: %i[id title body cancel_label destructive open_on_load],
        limits: [
          "The confirm action is the caller's slot: it performs no write of its own.",
          "It opens only through admin--ui--dialog, like every dialog: by its id, or marked by open_on_load."
        ],
        states: %i[rest destructive hover focus],
        script_states: {
          open: [ "test/system/dialog_test.rb", "a destructive confirm opens on Cancel, Escape backs out, confirming deletes" ]
        },
        keys: %w[cancel],
        slots: %i[confirm_action details],
        controller: nil
      )

      renders_one :confirm_action
      # Optional markup under `body`, for a confirmation that has to list
      # what it affects (deleting a group names the tokens it revokes).
      renders_one :details

      # `open_on_load:` is the shared dialog's: the dialog opens as soon as the
      # page appears.
      def initialize(id:, title:, body: nil, cancel_label: nil, destructive: false, open_on_load: false)
        @id = id
        @title = title
        @body = body
        @cancel_label = cancel_label
        @destructive = destructive
        @open_on_load = open_on_load
      end

      private

      attr_reader :id, :title, :body, :destructive, :open_on_load

      # A default argument can't ask `t`: nothing is rendering yet at `initialize`.
      def cancel_label = @cancel_label || t(".cancel")
    end
  end
end
