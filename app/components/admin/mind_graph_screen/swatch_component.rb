module Admin
  module MindGraphScreen
    # One swatch of the Mind graph's legend or Status key (pages in the mind
    # graph, spec §6): a small canvas with nothing on it. What is drawn there
    # is the graph's own renderer's (`mind_graph/swatches.js`, through
    # `admin--mind-graph--swatches` on the legend and on the key), so a
    # swatch is the mark or the line the canvas draws and not a copy of it
    # in SVG or CSS that could drift from it.
    #
    # THE SIZE IS THE SERVER'S, so that the row does not move when the swatch
    # is drawn: `SIZES` is each swatch's width and height in CSS pixels,
    # enough for the mark at the canvas's smallest size and what hangs on it
    # (a pin, a notes badge, a corner dot's ring). The script reads it from
    # `data-width` and `data-height`, because it writes the bitmap's own size
    # (the device's pixels) into `width` and `height`. The names are the
    # scenes' in `mind_graph/swatches.js`, and
    # `test/system/admin/mind_graph_modules_test.rb` holds the two lists
    # equal and every drawing inside its size.
    #
    # Decoration: the name stands beside it, so it is hidden from a screen
    # reader and is no stop for the keyboard.
    class SwatchComponent < AdminComponent
      MARK = [ 18, 18 ].freeze
      LINE = [ 22, 8 ].freeze
      SIZES = {
        page: [ 16, 12 ], post: MARK, tag: [ 12, 12 ], type: [ 14, 14 ],
        "line-tree": LINE, "line-lists": LINE, "line-related": LINE, "line-tag": LINE,
        "state-live": MARK, "state-draft": MARK, "state-scheduled": MARK, "state-live-with-changes": MARK, "state-live-change-scheduled": MARK,
        retired: MARK, pinned: [ 20, 20 ], notes: [ 26, 22 ]
      }.freeze

      def initialize(name)
        @name = name.to_sym
        @width, @height = SIZES.fetch(@name)
      end

      def call
        tag.canvas(class: "mg-swatch", width: @width, height: @height, "aria-hidden": true, data: { swatch: @name, width: @width, height: @height })
      end
    end
  end
end
