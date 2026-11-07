module Admin
  module Ui
    # The one native modal `<dialog>` every CS Studio dialog is built from: a
    # titled header with a close button, a scrolling body and an optional
    # footer for the actions. `Ui::ConfirmDialogComponent` is this plus a Cancel
    # and a confirm slot; a form dialog (new post, rename) passes its own
    # footer.
    #
    # Opening is `Admin::DialogController` (`admin--ui--dialog`), one instance on
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
      include Admin::Ui::Contract

      contract(
        accessibility: "A native modal dialog named by its title (aria-labelledby) with a Close button; Escape closes it, and the browser keeps the focus inside while it is open.",
        motion: :none,
        content_edges: %i[long short],
        widths: :fixed,
        interface: %i[id title width destructive open_on_load hang steady],
        limits: [
          "It draws the frame, the title, Close and the footer slot: the actions and the form inside are the caller's.",
          "It opens only through admin--ui--dialog on the body, by its id or marked by open_on_load."
        ],
        states: %i[rest hover focus],
        script_states: { open: [ "test/system/dialog_test.rb", "a destructive confirm opens on Cancel, Escape backs out, confirming deletes" ] },
        keys: %w[close],
        slots: %i[footer],
        controller: "admin--ui--dialog"
      )

      WIDTHS = { confirm: 420, form_narrow: 460, form: 560, picker: 880 }.freeze

      renders_one :footer

      # `open_on_load:` marks a dialog the server wants open as soon as the page
      # appears (a form dialog whose submission was refused, with the message
      # inside it): `admin--ui--dialog` opens it on connect and on every Turbo load
      # and strips the attribute, so a Turbo cache restore never reopens it.
      #
      # `hang: true` is for a dialog whose height changes while it is open (the New
      # page and New post dialogs: a loading line first, then the form loads into
      # their shell): it hangs from a fixed top edge like the media picker
      # (`.admin-media-picker`) instead of being centred, because a centred dialog
      # moves its own header, and whatever is under the pointer, with every such
      # change. See the comment on `.admin-dialog[data-dialog-hang]`.
      #
      # `steady: true` is for a dialog whose content changes while it is open and
      # whose FOOTER is what a person is aiming at (the publish dialog: "Publish
      # changes" and an overview that arrives a moment later). `hang:` keeps the
      # top edge and lets the foot move; this fixes the height, so nothing of the
      # frame moves, and what is longer scrolls in the body. See the comment on
      # `.admin-dialog[data-dialog-steady]`.
      def initialize(id:, title:, width: :confirm, destructive: false, open_on_load: false, hang: false, steady: false)
        raise ArgumentError, "unknown dialog width #{width.inspect}" unless WIDTHS.key?(width)

        @id = id
        @title = title
        @width = width
        @destructive = destructive
        @open_on_load = open_on_load
        @hang = hang
        @steady = steady
      end

      private

      attr_reader :id, :title, :width, :destructive, :open_on_load, :hang, :steady
    end
  end
end
