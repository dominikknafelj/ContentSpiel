# Converts a `RichText::Document` to and from Markdown (design spec §3.4) --
# the shape MCP/AI tools read and write `posts.body`/`content_blocks.body`
# as, since neither a human nor an LLM should have to author raw Tiptap
# JSON by hand. `RichText::Document#to_markdown`/`.from_markdown` are the
# entry points everything else calls; this module (and the two private
# classes below) is where the actual walk happens.
#
# `.dump` walks a document top-down, exactly like `RichText::HtmlRenderer`,
# driven by each type's own `markdown_out` block (`RichText::BuiltIns`) --
# but unlike HTML, "how do I combine my rendered children into my own
# output" genuinely differs per type (a paragraph's text runs concatenate
# with no separator; a blockquote's blocks stack with blank lines between
# them and then get "> "-prefixed as a whole; a list's items get numbered
# or bulleted, which only the list itself can do since a `listItem` has no
# way to know its own position). So, unlike `RichText::HtmlRenderer`'s
# single `safe_join` for every node, `Dumper#render_node` below picks one
# of three child-joining strategies by node type (inline concatenation,
# blank-line-joined blocks, or a raw Array of per-item strings for
# bulletList/orderedList to number themselves) before ever calling that
# type's own `markdown_out` block -- see the comment at
# `Dumper::BLOCK_CONTAINER_TYPES` for the full reasoning.
#
# `.load` parses with `Commonmarker.parse` (the `commonmarker` gem, added
# to the Gemfile this task) and walks *its* AST instead -- never calling
# Commonmarker's own `#to_html`, so its `unsafe` raw-HTML rendering path
# never runs; this only ever reads the parsed tree. `.load` never raises:
# an MCP-authored document is exactly as untrusted as a hand-edited jsonb
# row (`RichText::Document#validate`'s own reasoning), so anything this
# can't represent -- a raw HTML block, a plain-URL image, a table, an
# unsafe link scheme, a bad YouTube id, a `cs:` link to nothing, an unknown
# directive -- is dropped or degraded to plain text, and reported back as a
# warning String rather than failing the write outright.
module RichText
  module Markdown
    # A directive line is a paragraph on its own, consisting of exactly one
    # `::name{key="value" ...}` run and nothing else (design spec §3.4) --
    # `youtube`/`image` are the only built-ins that use one today, but any
    # future custom node type can register its own `directive` name
    # (`RichText::Schema::TypeDefinition#directive`) and be found the same
    # way (`Loader::DIRECTIVE_NODE_NAMES`).
    DIRECTIVE_PATTERN = /\A::([a-z][\w\/-]*)\{(.*)\}\z/

    # `key="value"` pairs inside a directive's braces, allowing a
    # backslash-escaped quote or backslash inside the value (mirroring
    # `#escape_directive_attr` below, its own inverse).
    ATTRIBUTE_PATTERN = /([A-Za-z_][\w-]*)="((?:\\.|[^"\\])*)"/

    # Markdown inline syntax characters that mean something to CommonMark
    # wherever they appear in a text run -- backslash first (so escaping it
    # doesn't double-escape whatever this same pass just inserted; a single
    # regex substitution handles the whole String in one pass, so there's
    # no second pass to corrupt). A Tiptap "text" node's `"text"` is always
    # plain, literal content -- any structure in the rendered Markdown
    # (bold, a link) comes from marks wrapping it, never from characters
    # already sitting in the text itself -- so every character below is
    # escaped unconditionally, not just where it would currently be
    # ambiguous: two adjacent text nodes (say, a plain run right after a
    # bolded one) concatenate with no separator, so an unescaped `*` at the
    # end of one and the start of the next could accidentally spell out a
    # `**` this document never had.
    ESCAPE_CHARS = /[\\`*_\[\]<>~]/

    # A line-*leading* character or sequence CommonMark treats as a block
    # marker (ATX heading, blockquote, thematic break/bullet, fenced code,
    # an ordered-list marker) rather than as ordinary paragraph text --
    # checked (and escaped) only once, against a paragraph's fully-assembled
    # text, never per text-node: `ESCAPE_CHARS` already protects every
    # occurrence of these chars *elsewhere* in a run, but a mark can
    # legitimately put one at position 0 on purpose (`**bold start**`), so
    # this only fires for what's actually literal, unmarked-up text sitting
    # at the very front of the paragraph.
    LEADING_BLOCK_CHARS = /\A([#>~`+-])/
    LEADING_ORDERED_MARKER = /\A(\d+)([.)])/

    class << self
      def dump(document) = Dumper.new.dump(document)
      def load(markdown) = Loader.new(markdown).load

      # Escapes a single text node's literal content (see `ESCAPE_CHARS`).
      # Shared between `Dumper#render_text_node` and `BuiltIns`' `code`
      # mark, which needs the *unescaped* raw text instead (code spans are
      # literal in Markdown; escaping them would leave literal backslashes
      # in the reloaded text) -- see `Dumper#render_text_node`'s own
      # comment for the full "raw" story.
      def escape_text(text) = text.gsub(ESCAPE_CHARS) { |char| "\\#{char}" }

      # Escapes whatever's sitting at the very front of a fully-rendered
      # paragraph, if (and only if) it would otherwise be read as a block
      # marker instead of the start of a plain paragraph -- see
      # `LEADING_BLOCK_CHARS`'s own comment. Also covers this module's own
      # directive syntax: a paragraph whose literal text happens to *look*
      # like `::name{...}` must not come back as that directive on reload
      # (see `Loader#directive_source_for`, which checks the raw Markdown
      # source rather than the parsed text for exactly this reason) -- this
      # is what makes that check actually correct instead of merely
      # untriggered by luck: escaping the leading `:` here means the
      # *source* this method's output produces no longer starts with a bare
      # `::`, while CommonMark still resolves the backslash away and hands
      # the reloaded text node back its original, unescaped `::...` string.
      def escape_leading(text)
        return text if text.empty?
        return text.sub(LEADING_BLOCK_CHARS) { "\\#{Regexp.last_match(1)}" } if text.match?(LEADING_BLOCK_CHARS)
        return text.sub(LEADING_ORDERED_MARKER) { "#{Regexp.last_match(1)}\\#{Regexp.last_match(2)}" } if text.match?(LEADING_ORDERED_MARKER)
        return "\\#{text}" if text.start_with?("::")

        text
      end

      # A Markdown link destination needs angle-bracket wrapping
      # (`<https://example.com/a b>`) when it contains a space or a
      # parenthesis -- either would otherwise be read as the end of the
      # `(...)` destination itself. Every href reaching this has already
      # passed `RichText::BuiltIns.safe_href?` (an http(s)/mailto/relative
      # scheme), so this is purely about the destination's own syntax, not
      # about safety.
      def escape_link_destination(href) = href.match?(/[\s()]/) ? "<#{href}>" : href

      # The inverse of `Dumper`'s own directive-attribute rendering
      # (`escape_directive_attr` below): backslash-escapes a `"` or `\\`
      # inside a directive attribute's value so it can sit inside the
      # `key="value"` pair without ending the value early.
      def escape_directive_attr(value) = value.to_s.gsub("\\", "\\\\\\\\").gsub('"', "\\\"")

      # `ATTRIBUTE_PATTERN`'s inverse for a value already captured between
      # the (still-escaped) quotes.
      def unescape_directive_attr(value) = value.gsub(/\\(.)/) { Regexp.last_match(1) }
    end

    # Walks a `RichText::Document`'s Hash and produces a Markdown String,
    # calling each node/mark's own `markdown_out` block for the parts only
    # that type knows how to format (see this file's own top comment for
    # why "how do children combine" isn't as uniform as HTML's `safe_join`).
    class Dumper
      # Types whose `"content"` is a list of *block* children -- rendered
      # one at a time, then joined with a blank line between each (the
      # Markdown separator between any two block-level elements), before
      # ever reaching that type's own `markdown_out` block. `doc` and
      # `blockquote`/`listItem` all share this shape: "some number of
      # blocks, stacked". `bulletList`/`orderedList` do *not* belong here
      # even though their `"content"` is also block-shaped (a list of
      # `listItem`s) -- seeing this file's own comment on
      # `LIST_CONTAINER_TYPES` for why those two need something richer than
      # a single joined String.
      BLOCK_CONTAINER_TYPES = %w[doc blockquote listItem].freeze

      # `bulletList`/`orderedList` render each `listItem` child on its own,
      # *without* joining them into one String first, and hand the result
      # to the list's own `markdown_out` as an Array -- not because listItem
      # isn't a "block", but because only the *list* knows how to prefix
      # each item (`"- "`, or `"1. "`/`"2. "`/... counting from
      # `attrs["start"]`) and re-indent that item's own continuation lines
      # underneath the marker. A `listItem`'s own `markdown_out` is the
      # identity block -- it contributes nothing but its already-rendered
      # content -- so the numbering/bulleting logic lives once, in
      # `RichText::BuiltIns`' `bulletList`/`orderedList` registration,
      # rather than every `listItem` needing to somehow know its own
      # position in its parent's `"content"` array.
      LIST_CONTAINER_TYPES = %w[bulletList orderedList].freeze

      # Prefixes `content` (one already-rendered `listItem`'s block-joined
      # Markdown, one or more lines) with `marker` (`"- "`/`"1. "`) on its
      # first line, and indents every continuation line underneath it by
      # `marker`'s own width -- a blank line (the separator between two
      # blocks inside a multi-block item) stays blank rather than gaining
      # trailing whitespace. A class method, not an instance one: it has no
      # need of `Dumper`'s own recursive walk, and `RichText::BuiltIns`'
      # `bulletList`/`orderedList` registration (the only other caller)
      # reaches for it without needing a `Dumper` instance of its own.
      def self.indent_list_item(marker, content)
        lines = content.split("\n", -1)
        indented = lines[1..].map { |line| line.empty? ? line : "#{" " * marker.length}#{line}" }
        ([ "#{marker}#{lines.first}" ] + indented).join("\n")
      end

      # Renders `document` (a `RichText::Document`) to a Markdown String,
      # always ending in exactly one trailing newline -- `Commonmarker
      # .parse` doesn't require one, but every other line this class emits
      # already ends in `"\n"` (each block joined by `"\n\n"`), so a
      # document with no trailing newline at all would be the one
      # inconsistency, and some Markdown tooling assumes a file-like String
      # always ends in one.
      def dump(document)
        text = render_node(document.to_h)
        text.end_with?("\n") ? text : "#{text}\n"
      end

      private

      # `raw`, once set by a `codeBlock` ancestor, propagates to every text
      # node underneath it: a code block's children are always bare "text"
      # nodes with no marks (`RichText::BuiltIns`' own comment on
      # `codeBlock`), and that literal source code must reach the fenced
      # code block byte-for-byte -- `RichText::Markdown.escape_text` would
      # otherwise backslash-escape characters that are supposed to render
      # unchanged inside the fence (and, worse, come back as literal
      # backslashes on reload, since a fenced code block's content isn't
      # subject to Markdown's own backslash-unescaping at all).
      #
      # Anything not a Hash (a `nil`, a bare Array/String slipped into
      # `"content"`) renders as nothing rather than raising -- the same
      # "never trust a document that skipped `#validate`" posture
      # `RichText::HtmlRenderer#render_node`/`RichText::Document
      # #validate_node` both take, for the same reason: this walks
      # `document.to_h` directly, not something `#validate` has necessarily
      # already passed over.
      def render_node(node, raw: false)
        return "" unless node.is_a?(Hash)
        return render_text_node(node, raw) if node["type"] == "text"

        type_name = node["type"]
        type = RichText::Schema.node(type_name)
        return "" if type.nil? || type.markdown_out.nil?

        node = normalize_attrs(node)
        content = node["content"]
        child_nodes = content.is_a?(Array) ? content : []

        children =
          if LIST_CONTAINER_TYPES.include?(type_name)
            child_nodes.map { |child| render_node(child) }
          elsif BLOCK_CONTAINER_TYPES.include?(type_name)
            child_nodes.map { |child| render_node(child) }.reject(&:empty?).join("\n\n")
          else
            child_nodes.map { |child| render_node(child, raw: raw || type_name == "codeBlock") }.join
          end

        type.markdown_out.call(node, children, nil)
      end

      # A "text" node has no `"content"` of its own to recurse into (see
      # `RichText::Document#validate_node`'s identical split) -- its
      # `"text"` is escaped first (unless `raw`, or the node itself carries
      # a `code` mark -- a code *span*'s content is exactly as literal as a
      # code *block*'s, and for the same reason), then each mark wraps it
      # in array order, innermost first, matching
      # `RichText::HtmlRenderer#render_text_node`'s own `reduce` -- one
      # convention for "what does mark order mean", shared by both
      # renderers, rather than two that could drift apart.
      def render_text_node(node, raw)
        text = node["text"].to_s
        marks = node["marks"].is_a?(Array) ? node["marks"] : []
        text = RichText::Markdown.escape_text(text) unless raw || marks.any? { |mark| mark.is_a?(Hash) && mark["type"] == "code" }
        content = marks.reduce(text) { |acc, mark_data| apply_mark(mark_data, acc) }

        RichText::Schema.node("text").markdown_out.call(node, content, nil)
      end

      # Same "skip anything malformed or unregistered instead of raising"
      # posture as `#render_node`, applied to a `"marks"` array entry.
      def apply_mark(mark_data, content)
        return content unless mark_data.is_a?(Hash)

        mark_data = normalize_attrs(mark_data)
        mark = RichText::Schema.mark(mark_data["type"])
        return content if mark.nil? || mark.markdown_out.nil?

        mark.markdown_out.call(mark_data, content, nil)
      end

      # Same normalization `RichText::HtmlRenderer#normalize_attrs` applies
      # before any `html` block runs -- every built-in `markdown_out` block
      # below reads `"attrs"` assuming it's a Hash.
      def normalize_attrs(node) = node["attrs"].is_a?(Hash) ? node : node.merge("attrs" => {})
    end

    # Parses a Markdown String into a `RichText::Document` Hash, via
    # `Commonmarker.parse`'s AST -- never `Commonmarker`'s own `#to_html`
    # (this file's own top comment). Never raises: every `render_*` method
    # below hands back *something* (an empty Array, at worst) rather than
    # letting a shape Commonmarker's parser produced -- or, for a directive,
    # a shape this file invented from raw source text -- reach
    # `RichText::Document#validate` unvetted. `#load` degrades what it can
    # (a bad YouTube id in a `::youtube{}`, a `cs:` link to nothing) and
    # simply drops what it can't (raw HTML, a table, a plain-URL image),
    # collecting a human-readable warning for each.
    class Loader
      def initialize(markdown)
        source = markdown.is_a?(String) ? markdown : markdown.to_s
        @source = source.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
      rescue StandardError
        @source = ""
      end

      # Returns `[RichText::Document, warnings]` (design spec §3.4) --
      # `warnings` is always an Array of Strings, empty when nothing had to
      # be dropped or degraded. The outer `rescue` is a last-resort net
      # underneath every other guard in this class: if Commonmarker's own
      # native parser ever raises on some input none of the guards below
      # anticipated, an MCP write still gets back an empty (valid) document
      # and a warning explaining why, rather than a 500.
      def load
        root = safe_parse
        content = root ? render_children(root) : []
        [ RichText::Document.new({ "type" => "doc", "content" => content }), @warnings ]
      rescue StandardError => e
        [ RichText::Document.empty, [ "failed to parse markdown: #{e.message}" ] ]
      end

      private

      def safe_parse
        @warnings = []
        Commonmarker.parse(@source, options: { extension: { table: false } })
      rescue StandardError => e
        @warnings << "failed to parse markdown: #{e.message}"
        nil
      end

      # Walks one AST node's direct children into an Array of Tiptap block
      # nodes -- shared by the document root, `blockquote`, and each list
      # `item`, all of which just hold "some number of blocks, in order"
      # (mirroring `Dumper::BLOCK_CONTAINER_TYPES`'s same three, on the way
      # out).
      def render_children(ast_node) = ast_node.each.flat_map { |child| render_block(child) }

      # One block-level Commonmarker node -> zero or more Tiptap block
      # nodes (zero for whatever this drops -- a raw HTML block, an
      # unsupported block type). A `:paragraph` is the one case that can
      # expand to something other than itself: `#directive_for` recognizes
      # our own `::name{...}` shape and replaces the whole paragraph with
      # the node it names, when it can.
      def render_block(node)
        case node.type
        when :paragraph then [ directive_for(node) || paragraph_node(node) ]
        when :heading then [ heading_node(node) ]
        when :list then [ list_node(node) ]
        when :block_quote then [ { "type" => "blockquote", "content" => render_children(node) } ]
        when :code_block then [ code_block_node(node) ]
        when :thematic_break then [ { "type" => "horizontalRule" } ]
        when :html_block
          @warnings << "dropped a raw HTML block"
          []
        else
          @warnings << "dropped unsupported block content (#{node.type})"
          []
        end
      end

      def paragraph_node(node) = { "type" => "paragraph", "content" => merge_text_runs(render_inline(node)) }

      # `header_level` clamped into the schema's declared `2..4` (Global
      # Constraints) -- untrusted Markdown can perfectly well contain a
      # level-1 or level-5+ ATX heading (`# `/`###### `), and clamping keeps
      # the heading's text instead of failing the whole write over
      # something this cheap to degrade.
      def heading_node(node)
        level = node.header_level.to_i.clamp(2, 4)
        { "type" => "heading", "attrs" => { "level" => level }, "content" => merge_text_runs(render_inline(node)) }
      end

      # Commonmarker's own AST splits a single literal run of text into
      # several sibling `:text` nodes wherever a backslash escape sits in
      # the middle of it (`#render_inline_node`'s `:escaped` case, its own
      # comment) -- this collapses any run of adjacent "text" nodes that
      # share the exact same `"marks"` back into one, so a paragraph this
      # class builds matches the single text node an editor (or an earlier
      # `#to_markdown`) would have produced for the same literal text.
      # `hardBreak`/other non-"text" nodes break a run (they're never
      # merged into, or across).
      def merge_text_runs(nodes)
        nodes.each_with_object([]) do |node, merged|
          previous = merged.last
          if previous && previous["type"] == "text" && node["type"] == "text" && previous["marks"] == node["marks"]
            previous["text"] = previous["text"] + node["text"]
          else
            merged << node.dup
          end
        end
      end

      # `attrs["start"]` is always set for an `orderedList` (defaulting to
      # `1`, CommonMark's own default when a list starts `"1. "`) so a
      # document with no explicit start number still round-trips to the
      # same attrs shape `RichText::BuiltIns`' `orderedList.start`
      # attribute expects -- see this file's own round-trip test.
      # `bulletList` has no attributes at all, so it never gets an
      # `"attrs"` key (matching `RichText::BuiltIns`' declaration).
      def list_node(node)
        items = node.each.map { |item| { "type" => "listItem", "content" => render_children(item) } }

        if node.list_type == :ordered
          { "type" => "orderedList", "attrs" => { "start" => node.list_start || 1 }, "content" => items }
        else
          { "type" => "bulletList", "content" => items }
        end
      end

      # `fence_info` is CommonMark's own name for a fenced code block's
      # language tag (` ```ruby `) -- empty (never `nil`) when the fence
      # carries none, so `"attrs"` is only set at all when there's a
      # language to record, matching `RichText::BuiltIns`' optional
      # `codeBlock.language`. The trailing newline `string_content` always
      # includes (every fenced code block's content ends in one, even a
      # single-line one) is stripped so this doesn't add a stray blank line
      # to the reloaded source that the original text node never had.
      def code_block_node(node)
        language = node.fence_info.to_s.strip
        text = node.string_content.to_s.sub(/\n\z/, "")
        attrs = language.empty? ? nil : { "language" => language }
        node_hash = { "type" => "codeBlock" }
        node_hash["attrs"] = attrs if attrs
        node_hash["content"] = [ { "type" => "text", "text" => text } ]
        node_hash
      end

      # Walks one inline Commonmarker node into zero or more Tiptap "text"
      # (or `hardBreak`) nodes. `marks_stack` accumulates outer-to-inner as
      # this descends into `emph`/`strong`/`strikethrough`/`link` -- a
      # leaf's actual `"marks"` Array is built innermost-first
      # (`#text_node`'s own `.reverse`), matching the same convention
      # `Dumper#render_text_node`/`RichText::HtmlRenderer#render_text_node`
      # both already use for mark order.
      def render_inline(ast_node, marks_stack = [])
        ast_node.each.flat_map { |child| render_inline_node(child, marks_stack) }
      end

      def render_inline_node(node, marks_stack)
        case node.type
        when :text then [ text_node(node.string_content.to_s, marks_stack) ]
        when :softbreak then [ text_node(" ", marks_stack) ]
        when :linebreak then [ { "type" => "hardBreak" } ]
        # A backslash-escaped character (`\*`, `\#`, ...) -- CommonMark's
        # own AST wraps it as an `:escaped` node around a single literal
        # `:text` child, rather than folding it into whatever `:text` run
        # surrounds it, which is exactly why `#paragraph_node`/
        # `#heading_node` run every result through `#merge_text_runs`
        # before building their node: without that merge, `to_markdown`'s
        # own escaping of a literal `"*not bold*"` would come back as
        # three separate text nodes (`"*"`, `"not bold"`, `"*"`) instead of
        # reassembling into the one text node it started as. Transparent
        # here, the same as `emph`/`strong`/... above -- it carries no mark
        # of its own, just its child's literal text.
        when :escaped then render_inline(node, marks_stack)
        when :emph then render_inline(node, marks_stack + [ { "type" => "italic" } ])
        when :strong then render_inline(node, marks_stack + [ { "type" => "bold" } ])
        when :strikethrough then render_inline(node, marks_stack + [ { "type" => "strike" } ])
        when :code then [ text_node(node.string_content.to_s, marks_stack + [ { "type" => "code" } ]) ]
        when :link then render_link(node, marks_stack)
        when :image
          @warnings << "dropped an image with a plain URL (#{node.url}); use an ::image{} directive instead"
          render_inline(node, marks_stack)
        when :html_inline
          @warnings << "dropped raw inline HTML"
          []
        else
          @warnings << "dropped unsupported inline content (#{node.type})"
          []
        end
      end

      def text_node(text, marks_stack)
        marks = marks_stack.reverse
        marks.empty? ? { "type" => "text", "text" => text } : { "type" => "text", "text" => text, "marks" => marks }
      end

      # `cs:page/<id>`/`cs:post/<id>` (design spec §3.4) become an
      # `internalLink` mark; any other safe href (`RichText::BuiltIns
      # .safe_href?`) becomes a plain `link`; anything else -- an unsafe
      # scheme, or a `cs:` target that doesn't exist -- drops the mark
      # entirely (keeping the link's own text) with a warning, exactly the
      # "hostile documents render inert" posture `RichText::BuiltIns`'
      # `html` blocks already take for the same two attributes.
      def render_link(node, marks_stack)
        mark = link_mark_for(node.url.to_s)
        render_inline(node, mark ? marks_stack + [ mark ] : marks_stack)
      end

      def link_mark_for(href)
        if href.start_with?("cs:page/", "cs:post/")
          internal_link_mark_for(href)
        elsif RichText::BuiltIns.safe_href?(href)
          { "type" => "link", "attrs" => { "href" => href } }
        else
          @warnings << "dropped a link with an unsafe href (#{href.inspect})"
          nil
        end
      end

      def internal_link_mark_for(href)
        type, id = href.sub("cs:", "").split("/", 2)
        mark = { "type" => "internalLink", "attrs" => { "type" => type, "id" => Integer(id.to_s, exception: false) } }
        return mark if valid_mark?(mark)

        @warnings << "dropped an internal link to a missing #{type} (#{id})"
        nil
      end

      # A directive is a paragraph consisting of exactly `::name{...}`, on
      # its own -- checked against the paragraph's *raw Markdown source*
      # (`#source_slice`), not its parsed/resolved text. See
      # `RichText::Markdown.escape_leading`'s own comment for why: backslash
      # escaping is invisible in a CommonMark node's resolved text (the
      # backslash is consumed during parsing either way), so checking the
      # *parsed* text could never tell a real directive apart from literal
      # text that merely looks like one. The raw source can: `to_markdown`
      # only ever escapes a *literal* paragraph's leading `::`, so a real
      # (unescaped) directive's source always starts with a bare `::`,
      # while an escaped literal's source starts with `\::` instead.
      def directive_for(node)
        raw = source_slice(node)
        return nil unless raw

        match = RichText::Markdown::DIRECTIVE_PATTERN.match(raw)
        return nil unless match

        build_directive(match[1], match[2], raw)
      end

      def source_slice(node)
        pos = node.source_position
        return nil unless pos.is_a?(Hash)

        lines = source_lines[(pos[:start_line] - 1)..(pos[:end_line] - 1)]
        return nil if lines.blank?

        lines.join.strip
      end

      def source_lines = @source_lines ||= @source.lines

      def build_directive(name, attrs_string, raw)
        attrs = parse_directive_attrs(attrs_string)

        case name
        when "youtube" then build_youtube_node(attrs, raw)
        when "image" then build_image_node(attrs, raw)
        else
          @warnings << "unknown directive #{raw.inspect}, kept as text"
          nil
        end
      end

      def parse_directive_attrs(attrs_string)
        attrs_string.to_s.scan(RichText::Markdown::ATTRIBUTE_PATTERN).each_with_object({}) do |(key, value), hash|
          hash[key] = RichText::Markdown.unescape_directive_attr(value)
        end
      end

      def build_youtube_node(attrs, raw)
        node = { "type" => "youtube", "attrs" => { "id" => attrs["id"].to_s } }
        return node if valid_node?(node)

        @warnings << "invalid youtube directive #{raw.inspect}, kept as text"
        nil
      end

      def build_image_node(attrs, raw)
        node_attrs = { "asset_id" => attrs["asset"] && Integer(attrs["asset"], exception: false) }
        node_attrs["alt"] = attrs["alt"] if attrs["alt"].present?
        node_attrs["caption"] = attrs["caption"] if attrs["caption"].present?
        node = { "type" => "image", "attrs" => node_attrs }
        return node if valid_node?(node)

        @warnings << "invalid image directive #{raw.inspect}, kept as text"
        nil
      end

      # Both `#valid_node?`/`#valid_mark?` check a single degraded-or-not
      # candidate by wrapping it in the smallest document that could ever
      # contain one and asking `RichText::Document#validate` -- deliberately
      # reusing the exact same rules `RichText::BuiltIns`' attribute
      # declarations already enforce (a real YouTube id, an existing
      # `MediaAsset`/`Page`/`Post`) rather than re-deriving them here, so
      # this loader can never silently drift out of sync with what those
      # declarations actually require.
      def valid_node?(node) = RichText::Document.new({ "type" => "doc", "content" => [ node ] }).validate.empty?

      def valid_mark?(mark)
        text_node = { "type" => "text", "text" => "x", "marks" => [ mark ] }
        RichText::Document.new({ "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ text_node ] } ] }).validate.empty?
      end
    end
  end
end
