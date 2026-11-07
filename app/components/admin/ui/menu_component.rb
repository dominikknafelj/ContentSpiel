module Admin
  module Ui
    # A popover menu: a button that owns a hidden `role="menu"`
    # panel, with what a native `<details>` lacks -- arrow-key movement,
    # Escape, closing on an outside click. It is what new menus use (the
    # rich-text toolbar's Insert menu, the language tabs' overflow, the editor
    # header's "⋯", a block card's "⋯", a posts-list row's "⋯" and the New post
    # split button's caret) -- there is no `<details>` menu left.
    # Each item is arbitrary content -- a `link_to` or a `button_to` -- and
    # `admin--ui--menu` gives every link or button inside the panel
    # `role="menuitem"` and the keyboard behaviour.
    #
    # `aria_label` names an icon-only trigger (the editor header's "⋯": the label
    # is the glyph, the name is "More actions"). `close_on_select` closes the
    # panel after a pick (`admin--ui--menu#select`), for a menu whose items open a
    # dialog or reveal a panel and so would otherwise stay open behind it;
    # without it the panel stays open after a pick.
    #
    # `list: true` is a panel that LISTS things and offers nothing to pick
    # (everyone who has a record open): the
    # panel is a `role="list"` of `listitem`s named by `list_label`, not a
    # menu, and its rows are plain text. Pressing the button opens it AND
    # MOVES THE FOCUS INTO IT, as one thing a screen reader reads through
    # (`tabindex="-1"`); Escape closes it and gives the focus back to the
    # button, and so does pressing the button again. Something inside the
    # button may also show it on hover without moving the focus
    # (`mouseenter->admin--ui--menu#reveal`, presence's "+N"). It closes when
    # neither the pointer nor the focus is on it any more
    # (`admin--ui--menu#leave`), and on a click outside. `panel_id` gives the
    # panel an id and the button its `aria-controls`.
    #
    # `columns: 2` or `3` lays the items out in a grid of that many columns
    # (the block menu is three), widening the panel to 34rem (never wider than
    # the window less its margins) and giving a button the grid cell's look; any
    # other count raises. `heading:` is a line of words before the items, hidden
    # from a screen reader because the panel is already named by `aria_label`.
    # The grid changes nothing the keyboard does: the items are still walked
    # one by one, in document order, which in a grid is reading order
    # (`admin--ui--menu#keydown`: ArrowDown/ArrowUp step to the next/previous).
    #
    # `align` is the edge the panel hangs from (`:right` is the right edge of
    # the button, for a menu at the end of a row); `button_class` replaces the
    # default button look, for a trigger that has to read as a tab or a link.
    class MenuComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A button with aria-haspopup and aria-expanded that opens a role=menu panel of menuitems (or a named list, which takes the focus), walked with the arrow keys, closed by Escape or a click outside.",
        motion: :none,
        content_edges: %i[short long many],
        widths: :fluid,
        interface: %i[label align button_class aria_label close_on_select list list_label panel_id columns heading],
        limits: [
          "Each item is the caller's own link or button: the menu gives it its role and its keyboard.",
          "It lays items out in one column, two or three, and another count is refused."
        ],
        states: %i[rest hover focus],
        script_states: {
          open: [ "test/system/admin/editor_header_test.rb", "the menu skips a disabled item: ArrowDown wraps past the homepage's disabled Move to trash" ]
        },
        keys: [],
        slots: %i[items],
        controller: "admin--ui--menu",
        keyboard: [ "test/system/admin/editor_header_test.rb", "the menu skips a disabled item: ArrowDown wraps past the homepage's disabled Move to trash" ]
      )

      renders_many :items

      def initialize(label:, align: :right, button_class: nil, aria_label: nil, close_on_select: false, list: false, list_label: nil, panel_id: nil, columns: nil, heading: nil)
        raise ArgumentError, "unknown menu alignment #{align.inspect}" unless %i[left right].include?(align)
        raise ArgumentError, "unknown menu column count #{columns.inspect}" unless [ nil, 2, 3 ].include?(columns)

        @label = label
        @align = align
        @button_class = button_class
        @aria_label = aria_label
        @close_on_select = close_on_select
        @list = list
        @list_label = list_label
        @panel_id = panel_id
        @columns = columns
        @heading = heading
      end

      private

      attr_reader :label, :align, :button_class, :aria_label, :close_on_select, :list, :list_label, :panel_id, :columns, :heading

      ACTIONS = "click@window->admin--ui--menu#closeOutside keydown->admin--ui--menu#keydown turbo:before-cache@document->admin--ui--menu#cache".freeze
      LIST_ACTIONS = "mouseleave->admin--ui--menu#leave focusout->admin--ui--menu#leave".freeze

      def actions = list ? "#{ACTIONS} #{LIST_ACTIONS}" : ACTIONS

      def button_action = list ? "admin--ui--menu#enter" : "admin--ui--menu#toggle"

      # What the button says it opens: a menu. A list's button says nothing
      # of the kind -- `aria-haspopup="true"` MEANS "menu", and what opens
      # is no menu of actions -- only that it is expanded or not, and, given
      # `panel_id`, which element that is (`aria-controls`).
      def popup = list ? nil : "menu"

      def panel_role = list ? "list" : "menu"

      # A list takes the focus itself; a menu's items do.
      def panel_options = list ? { tabindex: -1, aria: { label: list_label } } : {}

      def item_role = list ? "listitem" : "none"

      def panel_data = close_on_select ? { action: "click->admin--ui--menu#select" } : {}

      def button_classes = button_class || "inline-flex cursor-pointer items-center gap-1 rounded-cs px-2 py-1 text-sm text-meta hover:bg-sunken hover:text-ink"

      # Whole class strings, which Tailwind sees.
      GRID_CLASSES = { 2 => "grid grid-cols-2", 3 => "grid grid-cols-3" }.freeze
      GRID_PANEL = "w-[34rem] max-w-[calc(100vw-2rem)] gap-0.5".freeze
      LIST_BUTTON = "[&_button]:block [&_button]:w-full [&_button]:cursor-pointer [&_button]:rounded-cs [&_button]:px-2 [&_button]:py-1 [&_button]:text-left [&_button:hover]:bg-sunken [&_button:focus-visible]:bg-sunken".freeze
      # A grid cell is a chip and a name side by side; `flex` stands where the
      # list's `block` would, never beside it, so the two cannot fight.
      GRID_BUTTON = "[&_button]:flex [&_button]:w-full [&_button]:cursor-pointer [&_button]:items-center [&_button]:gap-2 [&_button]:rounded-button-sm [&_button]:px-1.5 [&_button]:py-1.5 [&_button]:text-left [&_button:hover]:bg-sunken [&_button:focus-visible]:bg-sunken".freeze

      def panel_classes
        # `admin-menu-panel`: the keyboard's row carries the stylesheet's accent bar.
        [ "admin-menu-panel absolute z-(--cs-z-popover) mt-1 min-w-44 rounded-card bg-popover shadow-3",
          (columns ? "#{GRID_CLASSES.fetch(columns)} #{GRID_PANEL} p-2.5" : "p-1"),
          ("focus:outline-none focus-visible:outline-2 focus-visible:outline-accent" if list),
          align == :right ? "right-0" : "left-0",
          "[&_[aria-current]]:bg-accent-tint [&_a]:block [&_a]:rounded-cs [&_a]:px-2 [&_a]:py-1 [&_a:hover]:bg-sunken [&_a:focus-visible]:bg-sunken",
          (columns ? GRID_BUTTON : LIST_BUTTON) ].compact.join(" ")
      end
    end
  end
end
