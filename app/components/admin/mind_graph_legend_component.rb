module Admin
  # The mind graph's legend (round 3, D27): one entry per content type PRESENT
  # among the posts the graph shows (not every registered type -- a legend of
  # types you can't see is noise, and a type the viewer can't read at all would
  # be disclosed by it), then the shapes: "Tag", "Draft or scheduled", and the
  # two edge kinds. Server-rendered so it is text and a real dot component, not
  # something the graph's JS draws; the swatches are small inline SVGs using
  # the graph's own token classes (`.mg-*` in content-spiel.tailwind.css), and
  # each carries its name beside it, so colour is never the only cue.
  #
  # A flat `Admin::` component: the namespace rules only forbid
  # `Admin::Media`, `Admin::Trash`, `Admin::Translations`, `Admin::AI`,
  # `Admin::Ai` and `Admin::Dashboard`.
  class MindGraphLegendComponent < AdminComponent
    # `content_types:` the type names of the shown posts, in any order, with
    # repeats allowed; they are de-duplicated here and listed in the registry's
    # order, an unregistered stored type last.
    def initialize(content_types:)
      @content_types = content_types.map(&:to_s).uniq
    end

    def type_names
      registered = ::ContentTypes.names.map(&:to_s)
      @content_types.sort_by { |name| [ registered.index(name) || registered.size, name ] }
    end
  end
end
