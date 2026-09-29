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
    # future custom node type can register its own `directive` name and
    # attribute mapping (`RichText::Schema::TypeDefinition#directive`) and
    # be found the same way, via `RichText::Schema.directive_node` --
    # `Loader#build_directive` looks the parsed name up there rather than
    # hardcoding which names are directives.
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
    #
    # `&` (review round 1's I4) for the same "unconditionally, not just
    # where currently ambiguous" reason: CommonMark recognizes HTML/numeric
    # character entities (`&copy;`, `&amp;`, `&#65;`) anywhere in a text
    # run and decodes them, with no way to tell "the editor typed a literal
    # ampersand that happens to be followed by a word and a semicolon" from
    # "this was meant as an entity" once it's plain text -- a backslash
    # before the `&` blocks that recognition (CommonMark §6.2's entity rule
    # only fires on an unescaped `&`) while resolving away to the literal
    # `&` on reload, the same mechanism `LEADING_BLOCK_CHARS`/`::` escaping
    # already relies on elsewhere in this file.
    ESCAPE_CHARS = /[\\`*_\[\]<>~&]/

    # A line-*leading* character or sequence CommonMark treats as a block
    # marker (ATX heading, blockquote, bullet list) rather than as ordinary
    # paragraph text -- checked (and escaped) only against a paragraph's
    # *first* child, and only when that child carries no marks at all
    # (`Dumper#render_text_node`'s `leading` parameter; review round 1's
    # I3 narrowed this down from "the paragraph's whole assembled text",
    # which incorrectly caught a leading `code` mark's own backtick fence
    # too -- indistinguishable, as a plain String, from literal text that
    # merely starts with a backtick).
    #
    # Backtick and tilde are deliberately *not* here, even though CommonMark
    # also treats a leading run of 3+ of either as a fenced-code-block
    # marker: `ESCAPE_CHARS` already backslash-escapes every literal
    # backtick/tilde a bare text node contains, at any position including
    # the front, so by the time this ever runs on genuinely unmarked
    # literal text there's no unescaped one left for this to catch.
    #
    # `=` and `|` (final fix wave, B) matter only at the start of a line
    # *after a hardBreak*, where a paragraph is already open: `===` would
    # turn the line before it into a setext heading, and a `|---|` row into
    # a table. Escaping them at a paragraph's very start too is harmless
    # (`\=` and `\|` are ordinary backslash escapes).
    LEADING_BLOCK_CHARS = /\A([#>+=|-])/
    LEADING_ORDERED_MARKER = /\A(\d+)([.)])/

    # Spaces/tabs at the start of a line (a paragraph's, or after a
    # hardBreak) are stripped by CommonMark -- four of them at a paragraph's
    # start even make an indented code block -- and so are spaces at a
    # paragraph's end. Backslash can't escape a space, so they're written
    # as numeric character references, which CommonMark decodes back to
    # the same characters without treating them as indentation.
    EDGE_WHITESPACE_ENTITIES = { " " => "&#32;", "\t" => "&#9;" }.freeze

    class << self
      def dump(document) = Dumper.new.dump(document)
      def load(markdown, known_references: nil) = Loader.new(markdown, known_references: known_references).load

      # Escapes a single text node's literal content (see `ESCAPE_CHARS`).
      # Shared between `Dumper#render_text_node` and `BuiltIns`' `code`
      # mark, which needs the *unescaped* raw text instead (code spans are
      # literal in Markdown; escaping them would leave literal backslashes
      # in the reloaded text) -- see `Dumper#render_text_node`'s own
      # comment for the full "raw" story.
      def escape_text(text) = text.gsub(ESCAPE_CHARS) { |char| "\\#{char}" }

      # The end-of-line counterpart of `#escape_leading`'s whitespace rule:
      # spaces/tabs ending a paragraph or heading become character
      # references (see `EDGE_WHITESPACE_ENTITIES`). In a heading, a trailing
      # run of `#` preceded by a space (or making up the whole text) would
      # also be read as an ATX closing sequence and dropped, so each `#` in
      # it is backslash-escaped.
      def escape_trailing(text, heading: false)
        text = text.sub(/[ \t]+\z/) { |run| run.gsub(/[ \t]/, EDGE_WHITESPACE_ENTITIES) }
        return text unless heading

        text.sub(/(\A|[ \t])(#+)\z/) { "#{Regexp.last_match(1)}#{Regexp.last_match(2).gsub("#", "\\#")}" }
      end

      # Escapes whatever's sitting at the very front of a paragraph's bare
      # first child, if (and only if) it would otherwise be read as a block
      # marker instead of the start of a plain paragraph -- see
      # `LEADING_BLOCK_CHARS`'s own comment. Also covers this module's own
      # directive syntax: a paragraph whose literal text happens to *look*
      # like `::name{...}` must not come back as that directive on reload
      # (see `Loader#directive_for`, which checks the raw Markdown source
      # rather than the parsed text for exactly this reason) -- this
      # is what makes that check actually correct instead of merely
      # untriggered by luck: escaping the leading `:` here means the
      # *source* this method's output produces no longer starts with a bare
      # `::`, while CommonMark still resolves the backslash away and hands
      # the reloaded text node back its original, unescaped `::...` string.
      def escape_leading(text)
        return text if text.empty?
        return text.sub(/\A[ \t]+/) { |run| run.gsub(/[ \t]/, EDGE_WHITESPACE_ENTITIES) } if text.match?(/\A[ \t]/)
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

      # Wraps a `code` mark's raw (never backslash-escaped -- `Dumper
      # #render_text_node`'s own comment) content in backticks per
      # CommonMark's actual code-span rule (spec §6.5), rather than the
      # fixed single backtick every other delimiter-wrapped mark can get
      # away with (review round 1's I3): the opening/closing run must be
      # *longer* than the longest run of consecutive backticks already
      # inside `content` (`` a`b `` needs a 2-backtick fence, not 1, or the
      # single backtick inside it would end the span early), and a single
      # space is added on each side whenever `content` itself starts or
      # ends with a backtick, so that backtick doesn't visually/
      # structurally merge with the fence. An empty `content` is a known,
      # narrow gap this doesn't close (there's no backtick-fenced spelling
      # of a *truly* empty code span that CommonMark parses back as one
      # rather than as literal backticks) -- not exercised by any built-in,
      # since every real code span has at least the one character a
      # `code` mark was applied to.
      def wrap_code_span(content)
        longest_run = content.scan(/`+/).map(&:length).max || 0
        fence = "`" * (longest_run + 1)
        # CommonMark also strips one space from each end of a code span
        # whose content both starts and ends with one (and isn't all
        # spaces) -- so content shaped like that needs the same padding,
        # which is then what gets stripped (final fix wave, B).
        spaced = content.start_with?(" ") && content.end_with?(" ") && content.match?(/[^ ]/)
        pad = !content.empty? && (content.start_with?("`") || content.end_with?("`") || spaced) ? " " : ""
        "#{fence}#{pad}#{content}#{pad}#{fence}"
      end
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
      #
      # Dumps `document.normalized` (final fix wave, B), not the raw Hash:
      # its edge-whitespace rule is what keeps a bold run like `"bold "`
      # from dumping as `**bold **`, which CommonMark reads as literal
      # asterisks -- and a stored document from before that rule existed
      # (or a hand-built one) must dump correctly too.
      def dump(document)
        text = render_node(document.normalized.to_h)
        text.end_with?("\n") ? text : "#{text}\n"
      end

      private

      # Known, accepted lossiness (fix round 1's m9): an empty `paragraph`
      # (no text, no marks) dumps to an empty String, which
      # `BLOCK_CONTAINER_TYPES`'s own `.reject(&:empty?)` then drops
      # entirely rather than emitting a blank line for it -- Markdown has
      # no way to *spell* an empty paragraph as its own block (a blank
      # line is just paragraph-separator syntax, not content), so a
      # spacer paragraph an editor left in on purpose doesn't survive a
      # Markdown round trip. Not worth solving: MCP is the only caller of
      # `.from_markdown` at all, and nothing meaningful is lost when the
      # thing being dropped was already empty.

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
      def render_node(node, raw: false, leading: false, trailing: false, heading: false)
        return "" unless node.is_a?(Hash)
        return render_text_node(node, raw, leading, trailing, heading) if node["type"] == "text"

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
            # Only "paragraph"'s own *first* child can ever need
            # `RichText::Markdown.escape_leading` (below) -- see
            # `#render_text_node`'s comment for why that's narrowed all the
            # way down to "an unmarked text node in that one position",
            # not "paragraph's fully-assembled text" (an earlier version
            # of this escape, fixed in review round 1's I3, ran against
            # the joined String instead and corrupted a leading `code`
            # mark's own backtick fence in the process -- indistinguishable,
            # as a plain String, from literal text that merely starts with
            # a backtick).
            render_inline_children(type_name, child_nodes, raw: raw || type_name == "codeBlock")
          end

        type.markdown_out.call(node, children, nil)
      end

      # A paragraph's/heading's (or codeBlock's) inline children, joined.
      # Line-edge escaping (final fix wave, B) applies to every *line*, not
      # just the paragraph's first: the text right after a hardBreak starts
      # a new source line too, where `- flour` would open a list, `# x` a
      # heading, `---` a setext underline -- so `leading` is set for the
      # first child and for every child following a hardBreak. `trailing`
      # is set for the last child, whose trailing spaces CommonMark strips.
      #
      # A hardBreak (or run of them) at the very *end* of a paragraph can't
      # be written at all -- `foo\` at the end of a block is a literal
      # backslash, not a break -- so trailing hardBreaks are left out: the
      # same accepted lossiness as an empty paragraph (a trailing empty
      # line), rather than corrupting the text with a stray backslash.
      #
      # An ATX heading is a single line, so a hardBreak inside one is
      # written as a space -- lossy the same way, but still one heading
      # with the same words, instead of `## a\` plus a new paragraph.
      def render_inline_children(type_name, child_nodes, raw:)
        line_escapes = %w[paragraph heading].include?(type_name)
        last_content = child_nodes.rindex { |child| !(child.is_a?(Hash) && child["type"] == "hardBreak") }
        child_nodes = child_nodes.first((last_content || -1) + 1) if line_escapes
        child_nodes = child_nodes.map { |child| child.is_a?(Hash) && child["type"] == "hardBreak" ? { "type" => "text", "text" => " " } : child } if type_name == "heading"

        child_nodes.each_with_index.map do |child, index|
          previous = index.zero? ? nil : child_nodes[index - 1]
          leading = line_escapes && (index.zero? || (previous.is_a?(Hash) && previous["type"] == "hardBreak"))
          trailing = line_escapes && index == child_nodes.size - 1
          render_node(child, raw: raw, leading: leading, trailing: trailing, heading: type_name == "heading")
        end.join
      end

      # A "text" node has no `"content"` of its own to recurse into (see
      # `RichText::Document#validate_node`'s identical split) -- its
      # `"text"` is escaped first (unless `raw`, or the node itself carries
      # a `code` mark -- a code *span*'s content is exactly as literal as a
      # code *block*'s, and for the same reason), then, if this is a
      # paragraph's own first child *and* it carries no marks at all,
      # `RichText::Markdown.escape_leading` runs next -- a marked-up first
      # child (bold, code, ...) is never at risk of being misread as a
      # different block type, only genuinely bare literal text is (review
      # round 1's I3's fix, narrowing what used to run against the whole
      # paragraph's assembled text instead). Every mark then wraps the
      # result in array order, innermost first, matching `RichText
      # ::HtmlRenderer#render_text_node`'s own `reduce` -- one convention
      # for "what does mark order mean", shared by both renderers, rather
      # than two that could drift apart.
      def render_text_node(node, raw, leading = false, trailing = false, heading = false)
        text = node["text"].to_s
        marks = node["marks"].is_a?(Array) ? node["marks"] : []
        text = RichText::Markdown.escape_text(text) unless raw || marks.any? { |mark| mark.is_a?(Hash) && mark["type"] == "code" }
        text = RichText::Markdown.escape_trailing(text, heading: heading) if trailing && marks.empty?
        text = RichText::Markdown.escape_leading(text) if leading && marks.empty?
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
    # simply drops what it can't (raw HTML, a plain-URL image), collecting
    # a human-readable warning for each.
    class Loader
      # `RichText::Document::MAX_DEPTH` bounds how far `#render_children`/
      # `#list_item_node` (block nesting) and `#render_inline_node` (mark
      # nesting) will descend, for two related but distinct reasons
      # (review round 1's C1/C2):
      #
      # Block nesting *has* to stay within this exact ceiling for
      # correctness, not just stack safety: a document this class builds
      # deeper than `RichText::Document#validate` itself allows would come
      # back invalid with no warning explaining why (a real regression a
      # 600-deep `> > > ... hi` input exposed) -- so once `depth` would
      # exceed it, the deeper content is dropped rather than built at all,
      # one warning recorded (`#warn_once`, not once *per* dropped node --
      # a pathological document could otherwise flood `warnings` with
      # thousands of near-identical messages).
      #
      # Mark nesting (`emph`/`strong`/`strikethrough`/`link`) has no such
      # correctness requirement -- however deep, it always flattens into
      # one leaf text node's flat `"marks"` Array, which has no structural
      # depth of its own once built -- but *building* it the way this
      # class currently does (recursing once per nesting level) still
      # spends one Ruby stack frame per level, and a `("> " * 5000) +
      # "hi\n"`-shaped input applied to emphasis instead of blockquotes
      # would blow the stack exactly the same way (`SystemStackError`,
      # never a `StandardError`, so `#load`'s own `rescue` alone can't
      # catch it -- this ceiling is what keeps the walk from ever reaching
      # that call in the first place). Past it, `#render_inline_node`
      # stops recursing and flattens whatever's left with
      # `#collect_plain_text`, which is iterative (no Ruby recursion at
      # all -- the same reason `RichText::Document#write_canonical`/
      # `#stringify` don't recurse either), so it stays safe regardless of
      # how much further the real nesting actually goes.
      MAX_DEPTH = RichText::Document::MAX_DEPTH

      # `known_references`: see `RichText::Document.from_markdown`. Only
      # `#valid_node?`/`#valid_mark?` read it -- the existence/readability
      # checks are the only rules a known reference is exempt from.
      def initialize(markdown, known_references: nil)
        @known_references = known_references
        source = markdown.is_a?(String) ? markdown : markdown.to_s
        @source = source.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
      rescue StandardError
        @source = ""
      end

      # Returns `[RichText::Document, warnings]` (design spec §3.4) --
      # `warnings` is always an Array of Strings, empty when nothing had to
      # be dropped or degraded. The outer `rescue` is a last-resort net
      # underneath every other guard in this class -- widened to
      # `SystemStackError` too (review round 1's C1), since Commonmarker's
      # own native parser has been observed to raise exactly that on
      # sufficiently extreme input (an extra guard `#safe_parse` also
      # takes, independently of this one, since parsing happens there
      # before any of this class's own depth-capped walking ever starts):
      # if either raises on something none of the guards below
      # anticipated, an MCP write still gets back an empty (valid) document
      # and a warning explaining why, rather than a 500.
      #
      # The built document then goes through `RichText::ContentRepair`
      # (final fix wave, A), so what comes back is always something the
      # editor can load, not merely something `#validate` used to accept --
      # its repairs join `warnings` like any other degrade.
      def load
        root = safe_parse
        content = root ? render_children(root, 1) : []
        repaired, repairs = RichText::ContentRepair.call({ "type" => "doc", "content" => content })
        repairs.each { |message| record_warning(message) }
        [ RichText::Document.new(repaired), @warnings ]
      rescue StandardError, SystemStackError => e
        Rails.logger.error("RichText::Markdown::Loader: #{e.class}: #{e.message}")
        [ RichText::Document.empty, [ "failed to parse markdown: #{e.message}" ] ]
      end

      private

      def safe_parse
        @warnings = []
        @depth_warned = {}
        Commonmarker.parse(@source, options: { extension: { table: true } })
      rescue StandardError, SystemStackError => e
        Rails.logger.error("RichText::Markdown::Loader: #{e.class}: #{e.message}")
        @warnings << "failed to parse markdown: #{e.message}"
        nil
      end

      # Every degrade/drop below goes through this instead of pushing onto
      # `@warnings` directly, so a written-off document's problems are
      # findable in the log the same way `RichText::HtmlRenderer
      # #log_unknown` already makes an unknown node/mark type findable --
      # `warnings` alone only reaches the MCP caller that requested this
      # particular write; the log is what a developer chasing "why did my
      # editor's content change" days later actually has.
      def record_warning(message)
        Rails.logger.warn("RichText::Markdown::Loader: #{message}")
        @warnings << message
      end

      # Same as `#record_warning`, but at most once per `key` for this
      # whole `#load` call -- for the one class of warning (nesting past
      # `MAX_DEPTH`) a single pathological document could otherwise
      # trigger thousands of times, once per node past the ceiling.
      def warn_once(key, message)
        return if @depth_warned[key]

        @depth_warned[key] = true
        record_warning(message)
      end

      # Walks one AST node's direct children into an Array of Tiptap block
      # nodes -- shared by the document root, `blockquote`, and each list
      # `item`, all of which just hold "some number of blocks, in order"
      # (mirroring `Dumper::BLOCK_CONTAINER_TYPES`'s same three, on the way
      # out). `depth` is what each of *this* call's direct children would
      # occupy in the resulting document (`RichText::Document#validate`'s
      # own convention: the root "doc"'s content is depth 1) -- passed
      # straight to `#render_block`, which is what actually enforces
      # `MAX_DEPTH` (`#render_block`'s own comment).
      def render_children(ast_node, depth) = ast_node.each.flat_map { |child| render_block(child, depth) }

      # One block-level Commonmarker node -> zero or more Tiptap block
      # nodes (zero for whatever this drops -- a raw HTML block, an
      # unsupported block type, or anything past `MAX_DEPTH`). A
      # `:paragraph` is the one case that can expand to something other
      # than itself: `#directive_for` recognizes our own `::name{...}`
      # shape and replaces the whole paragraph with the node it names,
      # when it can. A `:table` (review round 1's I5) is the one case that
      # can expand to *several* -- one paragraph per row, since nothing in
      # this schema represents a table -- rather than the single-element
      # Array every other branch returns.
      def render_block(node, depth)
        if depth > MAX_DEPTH
          warn_once(:depth, "dropped content nested past the maximum depth (#{MAX_DEPTH})")
          return []
        end

        case node.type
        when :paragraph
          directive = directive_for(node)
          return [] if directive == :drop

          [ directive || paragraph_node(node) ]
        when :heading then [ heading_node(node) ]
        when :list then [ list_node(node, depth) ]
        when :block_quote then [ { "type" => "blockquote", "content" => render_children(node, depth + 1) } ]
        when :code_block then [ code_block_node(node) ]
        when :thematic_break then [ { "type" => "horizontalRule" } ]
        when :table
          record_warning("degraded a table to one paragraph per row")
          table_rows_as_paragraphs(node)
        when :html_block
          record_warning("dropped a raw HTML block")
          []
        else
          record_warning("dropped unsupported block content (#{node.type})")
          []
        end
      end

      # This schema has no tabular node type at all (Global Constraints;
      # design spec §3.2's node list has no `table`), so a table can only
      # ever degrade, never translate -- one paragraph per `:table_row`,
      # its `:table_cell`s flattened to plain text (`#collect_plain_text`,
      # the same iterative flattening `#render_inline_node` falls back to
      # past `MAX_DEPTH`; a cell's own inline structure -- a bold cell, a
      # link -- isn't worth preserving for content this degraded already)
      # and joined with `" | "`, a plain-text echo of the pipes the
      # original table syntax used, so the degraded paragraph still *reads*
      # like tabular data instead of running every cell together.
      def table_rows_as_paragraphs(table_node)
        table_node.each.map do |row|
          text = row.each.map { |cell| collect_plain_text(cell) }.join(" | ")
          { "type" => "paragraph", "content" => text.empty? ? [] : [ { "type" => "text", "text" => text } ] }
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
      #
      # `depth` here is the *list's own* depth (already confirmed `<=
      # MAX_DEPTH` by `#render_block`'s own check before this is ever
      # called) -- each `listItem` occupies `depth + 1`, checked by
      # `#list_item_node` itself rather than `#render_block` (a listItem
      # is built directly here, not dispatched through `#render_block` the
      # way every other node type is), and that item's *own* children
      # occupy `depth + 2`.
      def list_node(node, depth)
        items = node.each.filter_map { |item| list_item_node(item, depth + 1) }

        if node.list_type == :ordered
          { "type" => "orderedList", "attrs" => { "start" => node.list_start || 1 }, "content" => items }
        else
          { "type" => "bulletList", "content" => items }
        end
      end

      def list_item_node(item, depth)
        if depth > MAX_DEPTH
          warn_once(:depth, "dropped content nested past the maximum depth (#{MAX_DEPTH})")
          return nil
        end

        { "type" => "listItem", "content" => render_children(item, depth + 1) }
      end

      # `fence_info` is CommonMark's own name for a fenced code block's
      # language tag (` ```ruby `) -- empty (never `nil`) when the fence
      # carries none, so `"attrs"` is only set at all when there's a
      # language to record, matching `RichText::BuiltIns`' optional
      # `codeBlock.language`. The trailing newline `string_content` always
      # includes (every fenced code block's content ends in one, even a
      # single-line one) is stripped so this doesn't add a stray blank line
      # to the reloaded source that the original text node never had.
      #
      # An empty fence is a code block with no `"content"` at all -- an
      # empty text node isn't allowed (final fix wave, A), and that's also
      # how the editor represents an empty code block.
      def code_block_node(node)
        language = node.fence_info.to_s.strip
        text = node.string_content.to_s.sub(/\n\z/, "")
        attrs = language.empty? ? nil : { "language" => language }
        node_hash = { "type" => "codeBlock" }
        node_hash["attrs"] = attrs if attrs
        node_hash["content"] = [ { "type" => "text", "text" => text } ] unless text.empty?
        node_hash
      end

      # Walks one inline Commonmarker node into zero or more Tiptap "text"
      # (or `hardBreak`) nodes. `marks_stack` accumulates as this descends
      # into `emph`/`strong`/`strikethrough`/`link` -- what order a leaf's
      # actual `"marks"` Array ends up in doesn't depend on *this* stack's
      # own order at all, though (`#text_node`'s own comment): it's sorted
      # into schema registration order, the same canonical order
      # `RichText::Document#normalized` defines (review round 1's I7).
      #
      # `depth` counts nesting purely for stack-safety (`MAX_DEPTH`'s own
      # comment) -- once it would exceed `MAX_DEPTH`, this stops recursing
      # per level and instead flattens whatever's left with
      # `#collect_plain_text` (iterative, so it's safe regardless of how
      # much further the real nesting goes).
      def render_inline(ast_node, marks_stack = [], depth = 0)
        ast_node.each.flat_map { |child| render_inline_node(child, marks_stack, depth) }
      end

      NESTING_INLINE_TYPES = %i[emph strong strikethrough link].freeze

      def render_inline_node(node, marks_stack, depth)
        if depth > MAX_DEPTH && NESTING_INLINE_TYPES.include?(node.type)
          warn_once(:inline_depth, "flattened inline formatting nested past the maximum depth (#{MAX_DEPTH})")
          return [ text_node(collect_plain_text(node), marks_stack) ]
        end

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
        when :escaped then render_inline(node, marks_stack, depth)
        when :emph then render_inline(node, marks_stack + [ { "type" => "italic" } ], depth + 1)
        when :strong then render_inline(node, marks_stack + [ { "type" => "bold" } ], depth + 1)
        when :strikethrough then render_inline(node, marks_stack + [ { "type" => "strike" } ], depth + 1)
        when :code then [ text_node(node.string_content.to_s, marks_stack + [ { "type" => "code" } ]) ]
        when :link then render_link(node, marks_stack, depth + 1)
        when :image
          record_warning("dropped an image with a plain URL (#{node.url}); use an ::image{} directive instead")
          render_inline(node, marks_stack, depth)
        when :html_inline
          record_warning("dropped raw inline HTML")
          []
        else
          record_warning("dropped unsupported inline content (#{node.type})")
          []
        end
      end

      # `RichText::Schema.mark_order` (registration order, e.g. bold before
      # italic before strike before code before link before internalLink
      # for the built-ins) rather than `marks_stack`'s own nesting order
      # (review round 1's I7) -- `[italic, bold]` and `[bold, italic]`
      # nested Markdown (`***hey***`, ambiguous either way once parsed)
      # both come back the one canonical order every editor-built document
      # already uses, instead of arbitrarily picking whichever nesting
      # order this parse happened to produce. An unregistered mark type
      # (`RichText::Schema.mark_order` returns `nil`) sorts after every
      # registered one, stably, rather than raising or reordering
      # arbitrarily -- there's no canonical position for a name the schema
      # doesn't know.
      def text_node(text, marks_stack)
        marks = marks_stack.sort_by { |mark| RichText::Schema.mark_order(mark["type"]) || Float::INFINITY }
        marks.empty? ? { "type" => "text", "text" => text } : { "type" => "text", "text" => text, "marks" => marks }
      end

      # Iteratively (no Ruby recursion -- the same reason `RichText
      # ::Document#write_canonical`/`#stringify` aren't recursive either)
      # flattens every descendant `:text`/`:code` node's literal content
      # into one plain String, dropping any mark structure along the way.
      # The one caller (`#render_inline_node`, past `MAX_DEPTH`) has
      # already given up on preserving nested formatting that deep, so
      # this only needs to recover the text, safely, regardless of how
      # much further the actual nesting goes.
      def collect_plain_text(ast_node)
        text = +""
        stack = ast_node.each.to_a.reverse

        until stack.empty?
          node = stack.pop
          case node.type
          when :text, :code then text << node.string_content.to_s
          when :softbreak then text << " "
          when :linebreak then text << "\n"
          else stack.concat(node.each.to_a.reverse)
          end
        end

        text
      end

      # `cs:page/<id>`/`cs:post/<id>` (design spec §3.4) become an
      # `internalLink` mark; any other safe href (`RichText::BuiltIns
      # .safe_href?`) becomes a plain `link`; anything else -- an unsafe
      # scheme, or a `cs:` target that doesn't exist -- drops the mark
      # entirely (keeping the link's own text) with a warning, exactly the
      # "hostile documents render inert" posture `RichText::BuiltIns`'
      # `html` blocks already take for the same two attributes.
      def render_link(node, marks_stack, depth)
        mark = link_mark_for(node.url.to_s)
        render_inline(node, mark ? marks_stack + [ mark ] : marks_stack, depth)
      end

      def link_mark_for(href)
        if href.start_with?("cs:page/", "cs:post/")
          internal_link_mark_for(href)
        elsif RichText::BuiltIns.safe_href?(href)
          { "type" => "link", "attrs" => { "href" => href } }
        else
          record_warning("dropped a link with an unsafe href (#{href.inspect})")
          nil
        end
      end

      def internal_link_mark_for(href)
        type, id = href.sub("cs:", "").split("/", 2)
        mark = { "type" => "internalLink", "attrs" => { "type" => type, "id" => Integer(id.to_s, exception: false) } }
        return mark if valid_mark?(mark)

        record_warning("dropped an internal link to a missing #{type} (#{id})")
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
      #
      # "Its own source" is the paragraph's own columns, not its whole lines
      # (final fix wave, B): inside a list item or a quote, the line also
      # holds the container's marker (`- ::youtube{...}`, `> ::image{...}`),
      # and the editor puts embeds there. A directive is always a
      # one-line paragraph, so a multi-line one is never one.
      #
      # Returns the node, `nil` (not a directive -- render the paragraph as
      # text) or `:drop` (a directive whose referenced record is gone, see
      # `#build_directive`).
      def directive_for(node)
        raw = source_slice(node)
        return nil unless raw

        match = RichText::Markdown::DIRECTIVE_PATTERN.match(raw)
        return nil unless match

        build_directive(match[1], match[2], raw)
      end

      # Commonmarker's columns are 1-based *byte* offsets, inclusive, so the
      # slice is a `byteslice`, re-encoded (a slice ending mid-character
      # can't be a directive anyway -- the pattern needs a closing `}`).
      def source_slice(node)
        pos = node.source_position
        return nil unless pos.is_a?(Hash) && pos[:start_line] == pos[:end_line]

        line = source_lines[pos[:start_line] - 1]
        return nil if line.nil?

        slice = line.byteslice((pos[:start_column] - 1)..(pos[:end_column] - 1)).to_s
        slice.force_encoding(Encoding::UTF_8).scrub("").strip
      end

      def source_lines = @source_lines ||= @source.lines

      # Schema-driven, not a hardcoded `case name when "youtube" ... when
      # "image" ...` (review round 1's I6): `RichText::Schema
      # .directive_node` finds whichever registered node type (built-in or
      # plugin) declared this directive `name`
      # (`RichText::Schema::TypeDefinition#directive`), and
      # `#attrs_from_directive` -- that same declaration's read half --
      # builds the candidate `"attrs"` Hash. `#valid_node?` is what decides
      # whether the result is actually usable (a bad YouTube id, a missing
      # `asset`) -- reusing the schema's own attribute rules rather than
      # this method re-deriving them, exactly as it already did before this
      # was made generic.
      def build_directive(name, attrs_string, raw)
        type = RichText::Schema.directive_node(name)
        unless type
          record_warning("unknown directive #{raw.inspect}, kept as text")
          return nil
        end

        node = { "type" => type.name, "attrs" => type.attrs_from_directive(parse_directive_attrs(attrs_string)) }
        return node if valid_node?(node, known_references: @known_references)

        # Valid except that a record it references no longer exists (an
        # image directive naming a deleted `Media::Asset`, final fix wave, B):
        # the directive was well-formed, the thing it embeds is gone, so it
        # goes -- as the public renderer would render it (nothing) -- rather
        # than turning into a paragraph of directive syntax.
        if valid_node?(node, known_references: RichText::Document.new(node).references)
          record_warning("dropped #{raw.inspect}: what it refers to no longer exists")
          return :drop
        end

        record_warning("invalid #{name} directive #{raw.inspect}, kept as text")
        nil
      end

      def parse_directive_attrs(attrs_string)
        attrs_string.to_s.scan(RichText::Markdown::ATTRIBUTE_PATTERN).each_with_object({}) do |(key, value), hash|
          hash[key] = RichText::Markdown.unescape_directive_attr(value)
        end
      end

      # Both `#valid_node?`/`#valid_mark?` check a single degraded-or-not
      # candidate by wrapping it in the smallest document that could ever
      # contain one and asking `RichText::Document#validate` -- deliberately
      # reusing the exact same rules `RichText::BuiltIns`' attribute
      # declarations already enforce (a real YouTube id, an existing
      # `Media::Asset`/`Page`/`Post`) rather than re-deriving them here, so
      # this loader can never silently drift out of sync with what those
      # declarations actually require.
      def valid_node?(node, known_references: nil) = RichText::Document.new({ "type" => "doc", "content" => [ node ] }).validate(known_references: known_references).empty?

      def valid_mark?(mark)
        text_node = { "type" => "text", "text" => "x", "marks" => [ mark ] }
        RichText::Document.new({ "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ text_node ] } ] })
          .validate(known_references: @known_references).empty?
      end
    end
  end
end
