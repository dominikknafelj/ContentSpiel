module Admin
  module Ui
    # "Unpublished changes": the rows of a published or scheduled record have
    # moved on from what the site shows. The status chip's
    # shell with a warn dot, in the editor's header and the posts list; the
    # page tree draws its own mark (`Admin::PagesScreen::TreeStateMarkComponent`).
    # Shared by two screens, so it lives here; WHEN to show it is `Publishing::State#changes?`, which
    # the caller asks.
    class UnpublishedChipComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Inline text, Unpublished changes, with its dot hidden from a screen reader; it takes no focus.",
        motion: :none,
        content_edges: %i[short],
        widths: :fluid,
        interface: [],
        limits: [
          "When to show it is Publishing::State#changes?, which the caller asks.",
          "The page tree draws its own mark, not this chip."
        ],
        states: %i[rest],
        keys: %w[label],
        slots: [],
        controller: nil,
        keyboard: "It takes no focus: a word in a row or a header whose own links and buttons the keyboard stops on."
      )
    end
  end
end
