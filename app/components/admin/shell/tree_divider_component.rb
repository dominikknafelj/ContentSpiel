module Admin
  module Shell
    # The divider on the page tree's right edge (Claude Design, 2026-10-13,
    # T1): the tree column is as wide as the person made it. A `separator`
    # that takes the focus and says its width (`aria-valuenow`, in pixels,
    # between `aria-valuemin` and `aria-valuemax`), which is ARIA's window
    # splitter: dragged with the pointer, moved with the arrow keys, reset by
    # a double click or Enter. Everything that moves is the script's
    # (`admin--shell--tree-width`); what is rendered here is the divider at
    # the default width, which is also what a browser without the script shows
    # (the column is then simply not adjustable).
    #
    # Rendered by the layout as the LAST child of `aside#tree-column`, after
    # the tree: outside `turbo-frame#tree`, which a move replaces, and after
    # every row, so the shell's drawer still moves the focus to the tree's
    # first link when it opens and Tab reaches the divider between the tree
    # and the editor, which is where it stands.
    #
    # THE NUMBERS are here once for the three that need them: this markup, the
    # layout's head script (`admin/shared/_tree_head`, which applies the
    # remembered width before the first paint) and the script, which reads them
    # from its values. They are the design's figures, which are PIXELS AT A
    # ROOT FONT SIZE OF 16PX: the stylesheet lays the shell out in rem
    # (`--admin-tree-column` in content-spiel.tailwind.css: 13.75rem, 17rem,
    # 30rem, 40rem, 15rem), and both scripts multiply each figure by the
    # root's font size over `BASE` before they use it, so a browser set to a
    # larger font gets a larger tree and a separator that says so. `NOTES`
    # alone is pixels at any font size, as `--admin-notes-width` is. The
    # stylesheet holds the figures as literals, since a media
    # query and `clamp()` cannot be handed a Ruby constant: change one, change
    # the other, and `test/system/admin/tree_column_test.rb` ("the maximum is
    # what leaves the editor 640px…") compares what the script allows with
    # what the grid draws.
    #
    # - `MIN`, `DEFAULT`, `MAX`: the column's narrowest, its width until
    #   someone chooses one (17rem, what it always was) and its widest.
    # - `EDITOR`: what the editor column keeps, whatever is asked: the
    #   narrowest width at which block cards and section lanes still work.
    #   The divider stops there before `MAX` on a narrow window.
    # - `SIDEBAR`: the modules sidebar, where it is a column of the grid (from
    #   1280px; below that it is a drawer and takes no room).
    # - `NOTES`: the notes drawer as a column (`--admin-notes-width`). With
    #   it open the tree stays beside the editor only while
    #   sidebar + tree + notes + `EDITOR` fit the window (T3).
    #
    # THE TOOLTIP is the shared one (`Admin::Ui::TooltipComponent`), with the
    # divider as its host: on keyboard focus at once, on hover after its own
    # wait. Its text names the current width, so the script writes it again
    # whenever the width changes, from the same key (`data-messages`). The
    # bubble hangs from a small sticky box (`.admin-tree-divider__tip`) and
    # not from the divider itself, which is as tall as the page: "under the
    # host" would be below the last row of a long page.
    class TreeDividerComponent < Admin::AdminComponent
      MIN = 220
      DEFAULT = 272
      MAX = 480
      EDITOR = 640
      SIDEBAR = 240
      NOTES = 400
      # The root font size the figures above are for (all but `NOTES`).
      BASE = 16
      # `localStorage`, per browser: a convenience, like the theme and the
      # notes drawer's "open".
      STORAGE_KEY = "cs-tree-width".freeze

      # A drag's moves, its release and its cancel are not here: the script
      # listens for them on the window for as long as a drag lasts. A lost
      # capture and the window's `blur` end a drag whose release never came.
      ACTIONS = %w[
        pointerdown->admin--shell--tree-width#press lostpointercapture->admin--shell--tree-width#release blur@window->admin--shell--tree-width#release
        pointerenter->admin--shell--tree-width#enter pointerleave->admin--shell--tree-width#leave
        dblclick->admin--shell--tree-width#reset keydown->admin--shell--tree-width#key focus->admin--shell--tree-width#sync
        resize@window->admin--shell--tree-width#sync turbo:frame-load@document->admin--shell--tree-width#sync
        turbo:before-cache@document->admin--shell--tree-width#rest
      ].join(" ").freeze

      def call
        tag.div(class: "admin-tree-divider", role: "separator", tabindex: 0,
          aria: { orientation: "vertical", controls: "tree-column", label: t(".label"), valuenow: DEFAULT, valuemin: MIN, valuemax: MAX },
          data: divider_data) do
          tag.span(class: "admin-tree-divider__tip") { render Admin::Ui::TooltipComponent.new(text: t(".tooltip", width: DEFAULT)) }
        end
      end

      private

      def divider_data
        tooltip = Admin::Ui::TooltipComponent.host_data
        {
          controller: "#{tooltip[:controller]} admin--shell--tree-width",
          action: "#{tooltip[:action]} #{ACTIONS}",
          "admin--shell--tree-width-min-value": MIN, "admin--shell--tree-width-default-value": DEFAULT, "admin--shell--tree-width-max-value": MAX,
          "admin--shell--tree-width-editor-value": EDITOR, "admin--shell--tree-width-sidebar-value": SIDEBAR, "admin--shell--tree-width-notes-value": NOTES,
          "admin--shell--tree-width-key-value": STORAGE_KEY,
          messages: messages_data("components.shell.tree_divider.tooltip")
        }
      end
    end
  end
end
