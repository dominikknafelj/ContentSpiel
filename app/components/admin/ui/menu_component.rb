module Admin
  module Ui
    # A popover menu (handoff §10): a button that owns a hidden `role="menu"`
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
    # dialog or reveal a panel and so would otherwise stay open behind it; the
    # older menus keep their panel open, as before.
    #
    # `list: true` is a panel that LISTS things and offers nothing to pick
    # (the people behind presence's "+N", presence handoff 6): the panel is a
    # `role="list"` of `listitem`s, not a menu, and it opens on hover and on
    # focus as well as on a click -- a click only ever opens it, since the
    # focus that precedes a click has opened it already and a toggle would
    # close it again. It closes on Escape, on a click outside, and when
    # neither the pointer nor the focus is on it any more
    # (`admin--ui--menu#leave`).
    #
    # `align` is the edge the panel hangs from (`:right` is the right edge of
    # the button, for a menu at the end of a row); `button_class` replaces the
    # default button look, for a trigger that has to read as a tab or a link.
    class MenuComponent < AdminComponent
      renders_many :items

      def initialize(label:, align: :right, button_class: nil, aria_label: nil, close_on_select: false, list: false)
        raise ArgumentError, "unknown menu alignment #{align.inspect}" unless %i[left right].include?(align)

        @label = label
        @align = align
        @button_class = button_class
        @aria_label = aria_label
        @close_on_select = close_on_select
        @list = list
      end

      private

      attr_reader :label, :align, :button_class, :aria_label, :close_on_select, :list

      ACTIONS = "click@window->admin--ui--menu#closeOutside keydown->admin--ui--menu#keydown".freeze
      LIST_ACTIONS = "mouseenter->admin--ui--menu#show mouseleave->admin--ui--menu#leave focusin->admin--ui--menu#show focusout->admin--ui--menu#leave".freeze

      def actions = list ? "#{ACTIONS} #{LIST_ACTIONS}" : ACTIONS

      def button_action = list ? "admin--ui--menu#show" : "admin--ui--menu#toggle"

      # What the button says it opens: a menu, or (a list) some popup.
      def popup = list ? "true" : "menu"

      def panel_role = list ? "list" : "menu"

      def item_role = list ? "listitem" : "none"

      def panel_data = close_on_select ? { action: "click->admin--ui--menu#select" } : {}

      def button_classes = button_class || "inline-flex cursor-pointer items-center gap-1 rounded-cs px-2 py-1 text-sm text-meta hover:bg-sunken hover:text-ink"

      def panel_classes
        [ "absolute z-30 mt-1 min-w-44 rounded-cs border border-line bg-surface p-1 shadow-menu",
          align == :right ? "right-0" : "left-0",
          "[&_a]:block [&_a]:rounded-cs [&_a]:px-2 [&_a]:py-1 [&_a:hover]:bg-sunken [&_a:focus-visible]:bg-sunken",
          "[&_button]:block [&_button]:w-full [&_button]:cursor-pointer [&_button]:rounded-cs [&_button]:px-2 [&_button]:py-1 [&_button]:text-left [&_button:hover]:bg-sunken [&_button:focus-visible]:bg-sunken" ].join(" ")
      end
    end
  end
end
