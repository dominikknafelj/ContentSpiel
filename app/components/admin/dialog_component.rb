module Admin
  # The one native modal `<dialog>` every CS Studio dialog is built from: a
  # titled header with a close button, a scrolling body and an optional
  # footer for the actions. `ConfirmDialogComponent` is this plus a Cancel
  # and a confirm slot; a form dialog (new post, rename) passes its own
  # footer.
  #
  # Opening is `Admin::DialogController` (`admin--dialog`), one instance on
  # `<body>`, looking the dialog up by id -- so a trigger anywhere (even
  # one a Turbo Stream or a `<turbo-frame id="content">` response put on
  # the page later) opens it; see `Admin::DialogHelper#dialog_trigger`.
  # Closing needs no JavaScript: the header's `<form method="dialog">`
  # closes the nearest open dialog, Esc is native, and a native modal
  # already traps focus -- none of that is re-implemented.
  #
  # The width is a named step (`WIDTHS`), mirrored as `data-dialog-width`
  # CSS in `content-spiel.tailwind.css` (a `<dialog>` needs real CSS for its
  # max size and backdrop); an unknown one is a programming error.
  class DialogComponent < AdminComponent
    WIDTHS = { confirm: 420, form_narrow: 460, form: 560, picker: 880 }.freeze

    renders_one :footer

    def initialize(id:, title:, width: :confirm, destructive: false)
      raise ArgumentError, "unknown dialog width #{width.inspect}" unless WIDTHS.key?(width)

      @id = id
      @title = title
      @width = width
      @destructive = destructive
    end

    private

    attr_reader :id, :title, :width, :destructive
  end
end
