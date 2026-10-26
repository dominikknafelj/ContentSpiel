module Admin
  module MindGraphScreen
    # The Mind graph's status key (pages in the mind graph, spec §6; design
    # answers "Status in the legend" and H6): the five looks a page or a post
    # can have on the canvas, each with its name. Status is NOT a filter, so
    # the looks are no toggles and not in the legend's row: the legend's
    # "Status key…" button opens this, CS Studio's one dialog, named "Status key".
    #
    # The names are THE CHIP'S WORDS (H6: one set of words): "Live,
    # unpublished changes" and "Live, change scheduled"; the day of a
    # scheduled change stands only on a card's chip. `STATES` are
    # `Publishing::State`'s names, in the key's order. A swatch is the
    # canvas's own mark, drawn by the graph's renderer (`SwatchComponent`).
    #
    # It is rendered once, by the screen's view, OUTSIDE the graph's element:
    # the Tab order of the box is the search, the graph and the list, and a
    # closed dialog's Close button is no stop in it. It is opened by the one
    # `admin--ui--dialog` controller on <body> and closed natively, and the
    # graph's script writes nothing in it (the swatches have a controller of
    # their own), so the graph's `reset` has nothing to take back here.
    class StatusKeyComponent < AdminComponent
      ID = "mind-graph-status-key".freeze
      STATES = %i[live draft scheduled live_with_changes live_change_scheduled].freeze
    end
  end
end
