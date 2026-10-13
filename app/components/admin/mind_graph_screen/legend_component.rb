module Admin
  module MindGraphScreen
    # The mind graph's legend, WHICH IS ITS FILTER (pages in the mind graph,
    # spec §6; design answers part one §4 and F6): the kinds of node and the
    # kinds of line are checkboxes, everything on, each with its count
    # ("Pages 200"), in place of the All / Related / Tags radios. After them
    # the "Status" link, and then the keys that switch nothing: one entry
    # per content type PRESENT among the viewer's readable posts (not every
    # registered type -- a legend of types you can't see is noise, and a
    # type the viewer can't read at all would be disclosed by it), "Retired
    # type" when one is present, "Pinned" (the mark of a node that stays
    # where it was dropped) and "Open notes" (the count badge of a post or a
    # page with open notes).
    #
    # WHICH TOGGLES A VIEWER GETS is `PostGraph::Kinds`' rule and nobody
    # else's: a kind that can be drawn for them has its toggle and its key,
    # and one that cannot has none (pages spec §2: no type the viewer cannot
    # read). So a reader of pages alone gets "Tags" too: a tag their pages
    # list is drawn. "Links in text" is not built and has no toggle, not
    # even a disabled one (F6).
    #
    # THE COUNTS ARE THE SCRIPT'S: the page holds no graph data, so a count
    # is empty here and written once the data has come (`mind_graph/app.js`),
    # with the checkbox's whole name ("Pages, 200"); the controller's `reset`
    # takes both back. A checkbox's state is the person's choice and is what
    # the graph shows.
    #
    # STATUS IS NOT A FILTER (the third design answers): the five looks are
    # a key of their own, a dialog (`StatusKeyComponent`, H6), and here is
    # only the "Status" link that opens it.
    #
    # Server-rendered, so every name is text and a type's dot is the real
    # component. A SWATCH is a small canvas (`SwatchComponent`) that the
    # graph's own renderer draws, through `admin--mind-graph--swatches` on
    # this element: the mark or the line the canvas draws, never a copy of
    # it. Each carries its name beside it, so colour is never the only cue.
    #
    # A flat `Admin::` component: a screen's namespace is named after the screen,
    # never after a domain module (`test/lib/admin_namespace_shadow_test.rb`), so
    # there is no `Admin::PostGraph`.
    class LegendComponent < AdminComponent
      # In the legend's order, which `mind_graph/graph_data.js` repeats
      # (`NODE_TOGGLES`, `LINE_TOGGLES`; a test holds the two equal).
      NODES = ::PostGraph::Kinds::NODES
      LINES = ::PostGraph::Kinds::LINES

      # `content_types:` the type names of the viewer's posts, in any order, with
      # repeats allowed; `pages:` whether the viewer can read a page at all.
      def initialize(content_types:, pages: false)
        @content_types = content_types.map(&:to_s).uniq
        @pages = pages
      end

      def node_toggles = kinds.fetch(:nodes)
      def line_toggles = kinds.fetch(:lines)

      # A toggle's swatch by its group and kind: "tag" is a kind of node and
      # a kind of line.
      def swatch_name(group, kind) = group == :lines ? "line-#{kind}" : kind

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

      private

      def kinds = @kinds ||= ::PostGraph::Kinds.shown(pages: @pages, posts: @content_types.any?)
    end
  end
end
