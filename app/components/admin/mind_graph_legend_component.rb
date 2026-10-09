module Admin
  # The mind graph's legend (round 3, D27; mind graph canvas spec §5.1): one
  # entry per content type PRESENT among the viewer's readable posts (not every
  # registered type -- a legend of types you can't see is noise, and a type the
  # viewer can't read at all would be disclosed by it), then the shapes: "Tag",
  # "Draft or scheduled", "Retired type" when one is present, the two edge
  # kinds, and "Pinned" (the mark of a node that stays where it was dropped) and "Open notes" (the count badge of a post with open notes). Server-rendered so it is text and a real dot component, not
  # something the graph's JS draws; the swatches are small inline SVGs using
  # the legend's own token classes (`.mg-*` in content-spiel.tailwind.css,
  # the same tokens `mind_graph/theme.js` hands the canvas), and each carries
  # its name beside it, so colour is never the only cue.
  #
  # A flat `Admin::` component: a screen's namespace is named after the screen,
  # never after a domain module (`test/lib/admin_namespace_shadow_test.rb`), so
  # there is no `Admin::PostGraph`.
  class MindGraphLegendComponent < AdminComponent
    # `content_types:` the type names of the viewer's posts, in any order, with
    # repeats allowed; they are de-duplicated here.
    def initialize(content_types:)
      @content_types = content_types.map(&:to_s).uniq
    end

    # Whether a shown post's type is no longer registered: such a post is drawn
    # as a grey ring with a stroke through it, and the legend says what that is.
    def retired? = (@content_types - ::ContentTypes.names.map(&:to_s)).any?

    # Only registered types get a dot of their own, in the registry's order. A
    # retired type has no colour slot to show, and its stored name is not a
    # label: all of them share the one "Retired type" entry.
    def type_names
      registered = ::ContentTypes.names.map(&:to_s)
      (@content_types & registered).sort_by { |name| registered.index(name) }
    end
  end
end
