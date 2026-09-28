module Admin
  # A native `<dialog>` for confirming a destructive action -- deleting a
  # page or post, renaming/deleting a tag that's in use (spec §5.3),
  # unpublishing (spec §5.1) -- opened by whatever triggered it (a
  # `ButtonComponent` elsewhere on the page calling
  # `document.getElementById(id).showModal()`, wired at the call site since
  # that's the only place that knows *when* confirmation is needed).
  #
  # Cancelling needs no JavaScript at all: a `<form method="dialog">`'s
  # submit closes the nearest open `<dialog>` per the HTML spec, so the
  # Cancel button below is a plain, unwired `<button>`. The actual confirm
  # action is a slot (`confirm_action`), not a `url:`/`method:` pair, so the
  # caller can render whatever it already uses to perform the write --
  # typically a `button_to` against a `Pages::Destroy`/`Tags::Destroy`-backed
  # route -- rather than this component reinventing Rails' own form helpers
  # for one method call.
  class ConfirmDialogComponent < AdminComponent
    renders_one :confirm_action
    # Optional markup under `body`, for a confirmation that has to list
    # what it affects (deleting a group names the tokens it revokes).
    renders_one :details

    def initialize(id:, title:, body: nil, cancel_label: "Cancel")
      @id = id
      @title = title
      @body = body
      @cancel_label = cancel_label
    end

    private

    attr_reader :id, :title, :body, :cancel_label
  end
end
