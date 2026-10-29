# Walks a `RichText::Document` (design spec §3.3) and renders it to HTML,
# driven entirely by what's registered on `RichText::Schema` -- every node
# and mark's own `html` block (registered in `RichText::BuiltIns`, and by
# any plugin later) decides how *it* renders; this class only walks the
# tree, escapes every raw text run before any block ever sees it, and runs
# the shared safety net every render must go through regardless of which
# blocks fired.
#
# `RichText::Document#to_html` is the entry point everything else calls (it
# also owns the render cache -- see that method's own comment for why
# caching lives there and not here); this class is exposed directly
# (`RichText::HtmlRenderer.new(context).render(document)`) for anything
# that builds its own `RenderContext` without going through the jsonb-
# column path a `Document` normally comes from.
#
# Components (`RichText::YoutubeComponent`, `RichText::ImageComponent`) are
# drawn by `RichText.component_renderer`, a callable the application assigns
# (`config/initializers/rich_text.rb`): this class isn't a controller action
# or a component itself, so it has no view context of its own, and a model
# naming a controller to get one is the dependency direction
# `test/lib/dependency_direction_test.rb` forbids.
#
# Tag construction goes through `ActionController::Base.helpers` -- a
# memoized helper proxy that already mixes in `ActionView::Helpers
# ::TagHelper` -- rather than this class including that module itself, so
# that the exact same proxy (`HELPERS` below) is reachable from
# `RichText::BuiltIns`'s `html` blocks too. Those blocks are plain Procs
# handed to `RichText::Schema.register_node`/`register_mark` at load time,
# and a Ruby block keeps the `self` (and hence its method lookup) it had at
# *definition* time -- `RichText::BuiltIns`, not whatever object ends up
# `.call`-ing it here -- so `include`-ing `TagHelper` into this class alone
# wouldn't make `tag`/`content_tag` reachable from inside those blocks.
module RichText
  class HtmlRenderer
    HELPERS = ActionController::Base.helpers

    def initialize(context)
      @context = context
    end

    # Renders `document` (a `RichText::Document`) to a scrubbed, html_safe
    # HTML String. Scrubbing happens once, here, against the *whole*
    # rendered tree, rather than piecemeal per node -- `RichTextScrubber`'s
    # youtube-nocookie iframe check in particular only makes sense evaluated
    # against a fully-formed `<iframe>` tag, not a half-built fragment a
    # single node's `html` block produced in isolation. This is the only
    # place `RichTextScrubber` is installed (it used to back ActionText's
    # own sanitizer too, until ActionText was removed) -- one safety net,
    # run at the very end of every path that turns a document into HTML,
    # including a plugin type's own `html` block.
    def render(document)
      html = render_node(document.to_h)
      Rails::HTML5::SafeListSanitizer.new.sanitize(html, scrubber: RichTextScrubber.new).html_safe
    end

    # Inline nodes (a table cell's paragraph content) drawn with no wrapper,
    # scrubbed as `render` scrubs: what a Table block's cell prints, in the
    # theme's own markup around it. Anything that is not a list of nodes is
    # nothing.
    def render_fragment(nodes)
      nodes = [] unless nodes.is_a?(Array)
      html = HELPERS.safe_join(nodes.map { |node| render_node(node, 1) })
      Rails::HTML5::SafeListSanitizer.new.sanitize(html, scrubber: RichTextScrubber.new).html_safe
    end

    # Many fragments at once (a Table block's cells, `RichText::Document#
    # table_cells_html`): Array<SafeBuffer>, one per list of nodes, each what
    # `render_fragment` would answer for it, from ONE parse and ONE scrubber
    # pass. A sanitizer pass per cell was most of what a large table cost:
    # 15,000 cells were 15,000 parses.
    #
    # Each fragment is drawn inside a `div` of its own, the whole is parsed and
    # scrubbed as `SafeListSanitizer#sanitize` does it (`Loofah.html5_fragment`,
    # `scrub!` with the scrubber, `to_html` in UTF-8: the gem's own three
    # steps, taken here so the wrappers can be split apart again before they
    # are serialised), and each wrapper's children are its fragment. A `div`
    # is what a cell's content lands in on its own too: a fragment's context
    # is the body, where a stray `tr` or `td` a hand-made cell renders is
    # dropped either way. The wrappers are only trusted when the parse left
    # exactly one `div` per fragment at the top; if it ever did not (markup
    # that escaped its wrapper), every fragment is drawn by `render_fragment`
    # alone, slow and right.
    def render_fragments(lists)
      lists = lists.map { |nodes| nodes.is_a?(Array) ? nodes : [] }
      return [] if lists.empty?

      html = HELPERS.safe_join(lists.map { |nodes| HELPERS.tag.div(HELPERS.safe_join(nodes.map { |node| render_node(node, 1) })) })
      fragment = Loofah.html5_fragment(html)
      fragment.scrub!(RichTextScrubber.new)
      wrappers = fragment.children
      unless wrappers.size == lists.size && wrappers.all? { |node| node.element? && node.name == "div" }
        return lists.map { |nodes| render_fragment(nodes) }
      end

      wrappers.map { |wrapper| wrapper.children.to_html(encoding: "UTF-8").html_safe }
    end

    private

    attr_reader :context

    # Every non-text node ("doc" down to "youtube"/"image") shares this
    # shape: recursively render whatever's in "content" first, then hand
    # the node's own registered `html` block the raw node Hash plus that
    # already-rendered, already-safe children string. A "text" node has no
    # "content" array at all (it carries a literal "text" String and an
    # optional "marks" array instead -- see `RichText::Document#validate_node`
    # for the same structural split), so it gets its own branch rather than
    # forcing that generic shape onto it.
    #
    # This has to be just as total as `RichText::Document#validate_node`
    # against a document that never passed `#validate` at all -- an
    # MCP-authored or hand-edited jsonb row, not something the editor could
    # ever produce -- since rendering runs unconditionally, not gated on
    # validity. `depth` is `RichText::Document::MAX_DEPTH`'s same recursion
    # guard, for the same reason (a long chain of single-child nodes would
    # otherwise blow the stack instead of failing gracefully); past it, a
    # node's content is simply dropped rather than rendered. `node.is_a?
    # (Hash)` is what makes every other malformed shape below safe: a `nil`
    # or a bare Array/String/Integer standing in for a node object (in
    # "content", or as the document root itself) lands here and renders as
    # nothing, logged, rather than raising the moment anything below tries
    # `node["type"]`.
    def render_node(node, depth = 0)
      return "".html_safe if depth > RichText::Document::MAX_DEPTH

      unless node.is_a?(Hash)
        log_unknown("node", node.inspect)
        return "".html_safe
      end

      node = normalize_attrs(node)
      return render_text_node(node) if node["type"] == "text"

      content = node["content"]
      child_nodes = content.is_a?(Array) ? content : []
      children = HELPERS.safe_join(child_nodes.map { |child| render_node(child, depth + 1) })

      type = RichText::Schema.node(node["type"])
      if type.nil?
        log_unknown("node", node["type"])
        return children
      end

      type.html.call(node, children, context)
    end

    # Escapes the raw "text" *before* any mark ever sees it -- every mark's
    # `html` block receives already-safe content and only ever wraps it, so
    # no block anywhere in the schema (built-in or plugin) can forget to
    # escape a user-authored string; there's simply no unescaped string left
    # by the time one runs. Marks then nest in their array order -- the
    # first mark wraps the raw escaped text (innermost), each later mark
    # wraps the previous result (progressively more outer) -- via `reduce`.
    #
    # `node["marks"]` given as anything but an Array (a Hash, most
    # plausibly -- ProseMirror JSON has no schema enforcement of its own) is
    # treated as "no marks" rather than coerced with `Array(...)`, the same
    # "checked, not coerced" rule `RichText::Document#validate_marks` uses
    # and for the same reason: `Array({"type" => "bold"})` reshapes a Hash
    # into `[["type", "bold"]]`, which would then hand `apply_mark` a
    # two-element Array instead of quietly doing nothing.
    def render_text_node(node)
      content = ERB::Util.html_escape(node["text"].to_s)
      marks = node["marks"]
      marks = marks.is_a?(Array) ? marks : []
      content = marks.reduce(content) { |html, mark_data| apply_mark(mark_data, html) }
      RichText::Schema.node("text").html.call(node, content, context)
    end

    # Same `is_a?(Hash)` guard `#render_node` uses, for a `"marks"` array
    # entry instead of a `"content"` one -- a stray non-object slipped into
    # `"marks"` is exactly as malformed as one slipped into `"content"`, and
    # gets the same "log and keep the content unmarked" treatment rather
    # than a `NoMethodError` from `mark_data["type"]`.
    def apply_mark(mark_data, content)
      unless mark_data.is_a?(Hash)
        log_unknown("mark", mark_data.inspect)
        return content
      end

      mark_data = normalize_attrs(mark_data)
      mark = RichText::Schema.mark(mark_data["type"])
      if mark.nil?
        log_unknown("mark", mark_data["type"])
        return content
      end

      mark.html.call(mark_data, content, context)
    end

    # Every built-in `html` block (`RichText::BuiltIns`) reads `"attrs"`
    # assuming it's a Hash -- `n["attrs"]["level"]`, `mark_data.dig("attrs",
    # "href")` -- because `RichText::Schema::Attribute`'s own DSL only ever
    # describes attributes as key/value pairs. A document that skips
    # `#validate` can hand a node/mark `"attrs"` of any shape at all (an
    # Array, a String, or simply omit it, leaving it `nil`), so every
    # `render_node`/`apply_mark` call normalizes it to a real (possibly
    # empty) Hash *before* any `html` block ever sees the node/mark --
    # one choke point, rather than every block added here or by a future
    # plugin having to re-guard its own `"attrs"` access.
    def normalize_attrs(node)
      node["attrs"].is_a?(Hash) ? node : node.merge("attrs" => {})
    end

    # Design spec §3.3: an unknown node or mark type is skipped (no wrapper
    # element, no attempt to interpret its "attrs") but its children's
    # already-rendered content is kept rather than dropped -- an editor
    # who authored a plugin-only block that later got uninstalled still
    # gets their text back, not a silent hole in the page -- and it's
    # logged, since a document referencing a type this schema doesn't know
    # about is worth a developer noticing.
    def log_unknown(kind, name)
      Rails.logger.warn("RichText::HtmlRenderer: unknown #{kind} type #{name.inspect}, keeping its rendered children")
    end
  end
end
