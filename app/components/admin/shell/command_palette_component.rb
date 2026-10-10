module Admin
  module Shell
    # The ⌘K "Jump to..." dialog (design pass spec §5.6, handoff §9): one
    # native modal <dialog> rendered once in the layout, outside `#content`
    # and every form, so its search input never feeds an autosave. The
    # `admin--shell--command-palette` controller on <body> opens it (⌘K / Ctrl+K,
    # or the sidebar and top-bar buttons), reloads `#jump-results` as the
    # viewer types, and moves the selection with the arrow keys.
    #
    # It isn't an `Admin::Ui::DialogComponent`: that one is a titled dialog with
    # a close button and a padded body, and the palette is a bare search
    # field over a results list. It does reuse the `.admin-dialog` CSS (the
    # backdrop and max-width) and so the body-level backdrop-click and Esc
    # handling `admin--ui--dialog` already gives every dialog.
    #
    # The frame has no `src` until the palette opens -- the controller sets
    # it then -- so no page load makes a request for a palette nobody
    # opened.
    class CommandPaletteComponent < Admin::AdminComponent
      ID = "command-palette".freeze

      # No parameters: the results URL is `data-admin--shell--command-palette-url-value`
      # on <body> (the controller's value), where it keeps the editing
      # language (`admin_url_options`) the layout already knows.
    end
  end
end
