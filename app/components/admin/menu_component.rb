module Admin
  # A popover menu (handoff §10): a button that owns a hidden `role="menu"`
  # panel, replacing the native `<details>` the first overflow menus used
  # (a `<details>` has no arrow-key movement, no Escape, no outside click).
  # Each item is arbitrary content -- a `link_to`, a `button_to`, or
  # `with_divider` -- and `admin--menu` gives every link or button inside the
  # panel `role="menuitem"` and the keyboard behaviour.
  #
  # `align` is the edge the panel hangs from (`:right` is the right edge of
  # the button, for a menu at the end of a row); `button_class` replaces the
  # default button look, for a trigger that has to read as a tab or a link.
  class MenuComponent < AdminComponent
    renders_many :items

    def initialize(label:, align: :right, button_class: nil)
      raise ArgumentError, "unknown menu alignment #{align.inspect}" unless %i[left right].include?(align)

      @label = label
      @align = align
      @button_class = button_class
    end

    def with_divider
      with_item { tag.div(role: "separator", class: "my-1 border-t border-line") }
    end

    private

    attr_reader :label, :align, :button_class

    def button_classes = button_class || "inline-flex cursor-pointer items-center gap-1 rounded-cs px-2 py-1 text-sm text-meta hover:bg-sunken hover:text-ink"

    def panel_classes
      [ "absolute z-30 mt-1 min-w-44 rounded-cs border border-line bg-surface p-1 shadow-menu",
        align == :right ? "right-0" : "left-0",
        "[&_a]:block [&_a]:rounded-cs [&_a]:px-2 [&_a]:py-1 [&_a:hover]:bg-sunken [&_a:focus-visible]:bg-sunken",
        "[&_button]:block [&_button]:w-full [&_button]:cursor-pointer [&_button]:rounded-cs [&_button]:px-2 [&_button]:py-1 [&_button]:text-left [&_button:hover]:bg-sunken [&_button:focus-visible]:bg-sunken" ].join(" ")
    end
  end
end
