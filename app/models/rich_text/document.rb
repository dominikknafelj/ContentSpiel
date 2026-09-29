# A value object around one Tiptap/ProseMirror JSON document (design spec
# §3.1) -- what `posts.body`/`content_blocks.body` store per locale, one
# `RichText::Document` per language. Immutable and comparison-friendly on
# purpose: models read one out of the jsonb column, editors and renderers
# read it back through `#to_h`/`#validate`/`#digest`, and nothing needs to
# mutate a document in place (an edit round-trips through the editor and
# writes a whole new Hash back).
#
# Conversions (`#to_html`, `#to_markdown`/`.from_markdown`, `.from_html`)
# each delegate to their own class -- `RichText::HtmlRenderer`,
# `RichText::Markdown`, `RichText::HtmlImport` -- so this file stays about
# the value itself: `.new`, `.empty`, `#to_h`, `#blank?`, `#digest`,
# `#validate` and `#normalized`.
module RichText
  class Document
    # The canonical "nothing here yet" document -- an empty `doc` node with
    # no children. `RichText::Document.new(nil)` (a brand-new, never-edited
    # locale) normalizes to this same shape rather than staying `nil`, so
    # every other method on this class can assume `@hash` is always a real
    # Tiptap document and never has to special-case "there's no document at
    # all".
    EMPTY_HASH = { "type" => "doc", "content" => [] }.freeze

    # A ceiling on how deep `#validate`/`#blank?` will recurse into
    # `"content"` nesting. Nothing a real editor produces gets remotely
    # close to this -- even a pathological amount of nested lists/quotes
    # tops out at a handful of levels -- so 50 is purely a safety valve
    # against a hostile or corrupted document (there's no schema-level
    # limit on Tiptap/ProseMirror nesting, and both `posts.body`/
    # `content_blocks.body` and MCP's Markdown-writer path can hand this
    # class a document that never went through the editor at all). Without
    # it, a document built as one long chain of nested nodes (worst case:
    # hundreds of `blockquote`s each wrapping the next) blows Ruby's call
    # stack with `SystemStackError` instead of failing `#validate` the same
    # way any other malformed document does -- see the regression test with
    # 500 nested `blockquote`s.
    MAX_DEPTH = 50

    def self.empty = new(EMPTY_HASH.deep_dup)

    # Deep-copies `value`, converting every Hash key to a String and every
    # Symbol *value* to a String too (fix round 1's addendum) -- run once,
    # here, at construction, so every other method on this class can
    # assume `@hash` never mixes Symbol and String keys or values. Two
    # real bugs motivate this, not just tidiness: `#digest`'s
    # `payload.keys.sort` raises `ArgumentError` the moment one Hash in the
    # tree has both a String and a Symbol key (`<=>` isn't defined between
    # them), which would make `#to_html` raise too (it computes `#digest`
    # for its cache key); and a Symbol value sitting where a String was
    # expected (`node["type"] == :text` instead of `"text"`) would silently
    # fail every `==`/`Schema.node(...)` lookup that assumes a String,
    # degrading a document instead of erroring. Neither is hypothetical --
    # a hand-built Hash (admin code, a test, MCP) has no way to guarantee
    # either on its own, and jsonb itself has no Symbol type to preserve
    # even if one slipped in before a save.
    #
    # Iterative, not recursive, for the exact same reason `#write_canonical`
    # is (that method's own comment): an admin form, MCP, or a hand-edited
    # jsonb row can hand this class a document nesting arbitrarily deep,
    # and this has to survive that just as safely as `#digest`/`#validate`
    # already do, not introduce a *third* place a pathologically deep
    # document can blow the stack. `container[key] = value` writes
    # directly into an already-allocated parent Hash/Array rather than
    # this returning a value up a call chain, which is what lets it rebuild
    # arbitrarily deep nested structure with a flat, heap-allocated stack
    # instead of one Ruby frame per level.
    def self.stringify(root)
      result_holder = [ nil ]
      stack = [ [ root, result_holder, 0 ] ]

      until stack.empty?
        value, container, key = stack.pop

        case value
        when Hash
          out = {}
          container[key] = out
          value.each { |k, v| stack << [ v, out, k.to_s ] }
        when Array
          out = Array.new(value.size)
          container[key] = out
          value.each_with_index { |v, index| stack << [ v, out, index ] }
        when Symbol
          container[key] = value.to_s
        else
          container[key] = value
        end
      end

      result_holder[0]
    end

    def initialize(hash)
      @hash = hash.nil? ? EMPTY_HASH.deep_dup : self.class.stringify(hash)
    end

    # Parses `markdown` (design spec §3.4) into `[RichText::Document,
    # warnings]`, where `warnings` is an Array of Strings, empty when
    # nothing had to be dropped or degraded -- MCP's write path for
    # `posts.body`/`content_blocks.body`. Delegates entirely to
    # `RichText::Markdown.load`; see that module's own comment for why the
    # conversion lives there rather than on this class (it's a big enough
    # walk, in both directions, to earn its own file, the same way
    # `RichText::HtmlRenderer` does for `#to_html` below). Never raises: an
    # MCP-authored String is exactly as untrusted as a hand-edited jsonb
    # row, so this degrades what it can't represent instead of failing the
    # whole write.
    #
    # `known_references` (access-control Task 10) is `#validate`'s own
    # parameter, passed through to the loader's per-link/per-embed checks:
    # the `#references` of the document this Markdown replaces. A link or
    # image already in the stored document is kept even when its target is
    # gone or unreadable to `Current.actor`, exactly as the admin editor
    # keeps it (`HasRichTextBody#body_errors_for`) -- otherwise a Markdown
    # round trip through `update_post` would silently strip every reference
    # the token can't see. `nil` (the default) checks everything: a new
    # body has nothing to be known against.
    def self.from_markdown(markdown, known_references: nil) = RichText::Markdown.load(markdown, known_references: known_references)

    # Converts stored ActionText/Trix HTML (design spec §5) into
    # `[RichText::Document, unmapped]` -- `unmapped` being one String per
    # piece of HTML that had no faithful equivalent (its text is kept where
    # it has any). Only `rich_text:migrate_from_action_text` needs this;
    # see `RichText::HtmlImport` for the mapping and its options.
    def self.from_html(html, **options) = RichText::HtmlImport.new(**options).call(html)

    def to_h = @hash

    # Renders this document to Markdown (design spec §3.4) -- MCP's read
    # path for `posts.body`/`content_blocks.body`. Delegates to
    # `RichText::Markdown.dump`; see `.from_markdown` above for why the
    # conversion itself lives on that module rather than here.
    def to_markdown = RichText::Markdown.dump(self)

    # Renders this document to a scrubbed, html_safe HTML String (design
    # spec §3.3), through `RichText::HtmlRenderer`. Defaults match what a
    # caller with no more specific `locale`/`urls` in hand should get: the
    # ambient `I18n.locale` and a non-preview `PublicSite::Urls` -- the same
    # defaults `PagesController`'s own public render path would reach for.
    #
    # Caching lives here rather than inside `RichText::HtmlRenderer` itself,
    # because the cache key (`RichText::Schema.version`, spec §3.3) needs
    # this document's own `#digest` plus the locale/preview it's being
    # rendered for -- all of which this method already has -- while the
    # renderer itself has no reason to know its own output is cacheable at
    # all; it just walks a document and returns HTML every time it's asked.
    # `RichText::Schema.version` is folded in so that a schema change (a new
    # built-in, or a plugin's type shape changing) invalidates every cached
    # render instead of serving stale HTML for a type whose rendering rules
    # just changed.
    #
    # `context.content_version` (fix round 1) is the site's content
    # fingerprint (`PublicSite.current_content_version`): the digest only
    # covers the document itself, but its HTML also depends on the world
    # around it -- an internal link renders as text until its target is
    # published, points at the target's *current* slug, and degrades to text
    # once the target is deleted; an image renders its `Media::Asset`'s URL, or
    # nothing once the asset is gone. Without it, Solid Cache would keep
    # serving the first render of each of those forever.
    #
    # `RichText.code_revision` (final fix wave, C) covers the last input:
    # the code itself. `Schema.version` only changes when a type's
    # *attributes* do; a changed `html` block or component template doesn't
    # touch it, and Solid Cache outlives a deploy.
    def to_html(locale: I18n.locale, urls: PublicSite::Urls.new)
      context = RichText::RenderContext.new(locale: locale, urls: urls, document: self)

      Rails.cache.fetch([ "rich_text", digest, RichText::Schema.version, locale, context.preview, context.content_version, RichText.code_revision ]) do
        RichText::HtmlRenderer.new(context).render(self)
      end
    end

    # "No text and no embeds" (spec §3.1) -- an empty paragraph, or a `doc`
    # with no content at all, is blank even though it's technically a valid
    # document; a lone `image` or `youtube` node with no text anywhere else
    # is *not* blank, since editors reasonably expect "just an embed, no
    # caption" to count as content. Walks the same `"content"` nesting
    # `#validate` does, rather than sharing code with it, because the two
    # walks stop for different reasons: this one can short-circuit the
    # instant it finds anything, `#validate` has to keep going to collect
    # every error.
    def blank? = !content?(@hash)

    # A stable content hash for the render cache key (spec §3.3) and for
    # "did this locale's document actually change" checks -- a canonical,
    # *key-sorted* serialization fed straight into a running `Digest::SHA256`,
    # not `JSON.generate` of a canonicalized deep copy. Ruby Hashes preserve
    # insertion order, so two documents that are semantically identical but
    # built up in a different order (e.g. attrs written `{"level" => 2,
    # "textAlign" => nil}` vs. the reverse) would digest differently if this
    # just hashed `JSON.generate(@hash)` directly; sorting each Hash's keys
    # before it's written is what makes those two identical again. Array
    # element order is left alone -- `"content"` order is meaningful (it's
    # the document's reading order), unlike Hash key order.
    #
    # `#to_html` computes this *before* it ever reaches
    # `RichText::HtmlRenderer` (it's part of the cache key), so it has to be
    # just as total against a pathologically deep or malformed document as
    # `#validate`/`RichText::HtmlRenderer` are -- but, unlike those two,
    # *never* at the cost of treating two distinct documents as the same
    # one: a cached render is keyed on this digest, and two documents that
    # collide here would serve each other's cached HTML (see this method's
    # git history for the exact bug -- an earlier version capped recursion
    # at `MAX_DEPTH` and replaced anything past it with a fixed placeholder,
    # which silently collapsed every leaf value past ~25 nesting levels to
    # that same placeholder, and did produce exactly that collision two
    # `AAAA`-vs-`BBBB` documents 24 levels deep). So this can't recurse
    # (Ruby method calls, unlike this loop's Array, share one bounded C
    # stack) and can't skip content at any depth -- see `#write_canonical`.
    def digest
      sha = Digest::SHA256.new
      write_canonical(@hash, sha)
      sha.hexdigest
    end

    # Walks the document against `RichText::Schema` and returns every
    # problem found, as plain message Strings -- empty when the document is
    # valid. Doesn't raise: a Post or ContentBlock's own model validation
    # (Task 4+) surfaces these the normal ActiveModel way, and a caller that
    # only wants "is this fine" can just check `.validate.empty?`.
    #
    # Every message names both the offending type and, where relevant, the
    # offending attribute (`"heading.level ..."`, `"link.href ..."`) --
    # callers and tests alike need to know not just *that* something's
    # wrong but which node or mark caused it, especially once a document
    # nests several of the same type.
    #
    # Never raises, even for a document shape that isn't just "wrong" but
    # actively malformed -- a `"content"`/`"marks"` array holding a
    # non-object, a `nil` slipped into `"content"`, `"content"`/`"marks"`
    # given as a Hash instead of an Array, nesting deep enough to blow the
    # stack. Every one of those is now an error message, not a `TypeError`/
    # `NoMethodError`/`SystemStackError` -- a Post or ContentBlock's model
    # validation (Task 4+) needs `#validate` to behave like any other
    # ActiveModel validation (return problems, don't crash the request),
    # and this document may never have passed through the editor or this
    # very method before reaching here (an MCP-authored Markdown document,
    # a hand-edited jsonb row) -- "malformed" has to be just another kind
    # of "invalid", not a 500.
    #
    # `known_references` (Task 7 fix round 1, I2): the `#references` of the
    # document this one replaces. An attribute declared `reference:` (an
    # existence check -- `image.asset_id`, `internalLink.id`) skips that
    # check for a reference already in the set: a link whose page was
    # deleted *after* it was saved must not make the whole document
    # unsaveable on the next, unrelated edit (the renderer already degrades
    # it). A reference that's new still has to exist. `nil` (the default)
    # checks everything, which is what every caller without a previous
    # document -- MCP, seeds, a new record -- wants.
    #
    # The content model (final fix wave, A) is part of "valid": which
    # children each node takes (`RichText::NodeType#content`), which marks
    # can share a text run (`RichText::MarkType#excludes`), no empty text
    # nodes, no marks outside inline content. These are ProseMirror's own
    # rules, restated -- the editor refuses to load a document that breaks
    # any of them, so accepting one here would store a body CS Studio can
    # then only show read-only.
    #
    # A root that isn't even a Hash (`Document.new(42)`, a jsonb value
    # that's an Array) is one error, not a `TypeError` from `42["type"]`.
    def validate(known_references: nil)
      return [ "the document's root node must be a \"doc\" object, got #{@hash.class.name}" ] unless @hash.is_a?(Hash)

      errors = []
      errors << "the document's root node must be \"doc\", got #{@hash["type"].inspect}" unless @hash["type"] == "doc"
      validate_node(@hash, errors, path: "root", depth: 0, known: known_references, parent: nil)
      errors
    end

    # Every reference (`RichText::Schema::Attribute#reference`) this
    # document makes, as a Set of `[type, attribute, value, *scope values]`
    # keys -- `["image", "asset_id", 42]`, `["internalLink", "id", 7,
    # "page"]`. Iterative and shape-tolerant like `#normalized`: this runs on
    # whatever the column holds, validated or not.
    def references
      found = Set.new
      stack = [ @hash ]
      until stack.empty?
        node = stack.pop
        next unless node.is_a?(Hash)

        type = RichText::Schema.node(node["type"])
        collect_references(type, node["attrs"], found) if type
        Array(node["marks"]).each { |mark| collect_references(RichText::Schema.mark(mark["type"]), mark["attrs"], found) if mark.is_a?(Hash) } if node["marks"].is_a?(Array)
        stack.concat(node["content"]) if node["content"].is_a?(Array)
      end
      found
    end

    # A new `RichText::Document` with every text node's `"marks"` Array
    # reordered into `RichText::Schema`'s own mark *registration* order
    # (fix round 1's I7) -- bold before italic before strike before code
    # before link before internalLink, for the built-ins. This is what
    # Tiptap/ProseMirror already keeps an editor-built document's marks in
    # (ProseMirror stores a node's marks sorted by the schema's own mark
    # index, not by whatever order an editor happened to apply them), so an
    # ordinary document is already canonical; this exists for the documents
    # that aren't -- most notably `RichText::Markdown::Loader`'s own input,
    # before that class settled on emitting schema order directly, and any
    # hand-built Hash a test or a script constructs with marks in some
    # other order.
    #
    # `#to_h`/`#digest`/`#validate` deliberately do *not* run this
    # automatically -- they report on the document exactly as given, the
    # same "report, don't silently rewrite" posture every other
    # malformed-shape guard on this class takes -- so round-trip exactness
    # through Markdown (`RichText::MarkdownTest`'s own round-trip test) is
    # only guaranteed against `#normalized`, not the raw `#to_h`, for a
    # document whose mark order wasn't already canonical to begin with:
    # `[italic, bold]` and `[bold, italic]` produce indistinguishable
    # Markdown (`***hey***` either way) and so can only ever come back as
    # one of the two -- the canonical one.
    #
    # Iterative, not recursive (`#stringify`'s own comment, same reason):
    # this may run on a document nobody has ever called `#validate` on.
    #
    # Also (final fix wave, B): whitespace at either edge of a bold/italic/
    # strike run moves outside the mark -- `"a"`, `" bold "` (bold), `"b"`
    # becomes `"a "`, `"bold"` (bold), `" b"` -- and a run that's *only*
    # whitespace loses those marks. It reads the same, and it's the only
    # shape Markdown can spell: CommonMark's flanking rules don't let
    # `**bold **` close (it comes back as literal asterisks), so without
    # this an ordinary editor habit -- bolding a word along with the space
    # after it -- corrupts the text on MCP's read/write round trip. Adjacent
    # text nodes whose marks are then equal are merged into one, as
    # ProseMirror itself would store them. Links and code keep their edge
    # whitespace (link text and code spans can hold it).
    def normalized = self.class.new(canonicalize_marks(@hash))

    # The marks whose Markdown delimiters are subject to CommonMark's
    # flanking rules (`#normalized`).
    FLANKING_MARKS = %w[bold italic strike].freeze

    private

    # One `"content"` Array's inline children, with `#normalized`'s edge-
    # whitespace rule applied and equal-marked neighbours merged. Anything
    # that isn't a well-formed text node passes through untouched.
    def hoist_edge_whitespace(children)
      pieces = children.flat_map do |child|
        next [ child ] unless child.is_a?(Hash) && child["type"] == "text" && child["text"].is_a?(String) && child["marks"].is_a?(Array)

        marks = sort_marks(child["marks"])
        flanking, other = marks.partition { |mark| mark.is_a?(Hash) && FLANKING_MARKS.include?(mark["type"]) }
        next [ child.merge("marks" => marks) ] if flanking.empty?

        lead, core, trail = child["text"].match(/\A([[:space:]]*)(.*?)([[:space:]]*)\z/m).captures
        next [ text_piece(child, core.empty? ? child["text"] : core, core.empty? ? other : marks) ] if core.empty? || (lead.empty? && trail.empty?)

        [ (text_piece(child, lead, other) unless lead.empty?), text_piece(child, core, marks), (text_piece(child, trail, other) unless trail.empty?) ].compact
      end

      pieces.each_with_object([]) do |piece, merged|
        previous = merged.last
        if mergeable_text?(previous) && mergeable_text?(piece) && Array(previous["marks"]) == Array(piece["marks"])
          merged[-1] = previous.merge("text" => previous["text"] + piece["text"])
        else
          merged << piece
        end
      end
    end

    def text_piece(node, text, marks) = marks.empty? ? node.except("marks").merge("text" => text) : node.merge("text" => text, "marks" => marks)

    def mergeable_text?(node) = node.is_a?(Hash) && node["type"] == "text" && node["text"].is_a?(String) && node.keys.difference(%w[type text marks]).empty?

    # `RichText::Schema.mark_order` (registration order) rather than
    # whatever order a `"marks"` Array already happens to be in -- an
    # unregistered mark type (`mark_order` returns `nil`) sorts after every
    # registered one, stably, rather than raising or reordering
    # arbitrarily; there's no canonical position for a name the schema
    # doesn't know.
    def sort_marks(marks)
      marks.each_with_index.sort_by { |mark, index| [ (mark.is_a?(Hash) ? RichText::Schema.mark_order(mark["type"]) : nil) || Float::INFINITY, index ] }.map(&:first)
    end

    # `#normalized`'s own walk -- structurally the same iterative
    # deep-rebuild `.stringify` is, except this one only ever transforms a
    # `"marks"` Array (via `#sort_marks`, leaving every mark Hash inside it
    # otherwise untouched -- a mark has no nested "content"/"marks" of its
    # own to further canonicalize) and passes every other Hash/Array/scalar
    # through unchanged.
    def canonicalize_marks(root)
      result_holder = [ nil ]
      stack = [ [ root, result_holder, 0 ] ]

      until stack.empty?
        value, container, key = stack.pop

        case value
        when Hash
          out = {}
          container[key] = out
          value.each do |k, v|
            if k == "marks" && v.is_a?(Array)
              out[k] = sort_marks(v)
            elsif k == "content" && v.is_a?(Array) && v.any? { |child| child.is_a?(Hash) && child["type"] == "text" }
              hoisted = hoist_edge_whitespace(v)
              stack << [ hoisted, out, k ]
            else
              stack << [ v, out, k ]
            end
          end
        when Array
          out = Array.new(value.size)
          container[key] = out
          value.each_with_index { |v, index| stack << [ v, out, index ] }
        else
          container[key] = value
        end
      end

      result_holder[0]
    end

    def content?(node, depth = 0)
      return false unless node.is_a?(Hash)
      return false if depth > MAX_DEPTH

      case node["type"]
      when "text" then node["text"].present?
      when "image", "youtube" then true
      else
        content = node["content"]
        content.is_a?(Array) && content.any? { |child| content?(child, depth + 1) }
      end
    end

    # Writes `value`'s canonical form straight into `sha`
    # (`Digest::SHA256#update`, called repeatedly rather than building one
    # giant String first) -- a Hash as `{`, its *sorted* keys each
    # JSON-encoded and colon-joined to their own canonicalized value,
    # comma-separated, then `}`; an Array the same shape with `[`/`]` and no
    # key sorting (element order is meaningful); anything else (String/
    # Integer/Float/true/false/nil, or a malformed node that's some other
    # JSON scalar where a Hash/Array belonged) via a single `JSON.generate`
    # call, which is safe because a scalar has no nesting of its own to
    # blow up on. None of this needs to round-trip back into a document --
    # nothing ever parses a digest -- so it doesn't have to *be* valid JSON,
    # only a stable, order-preserving, effectively-injective-via-SHA-256
    # encoding of the tree.
    #
    # Iterative, not recursive, with an explicit `stack` Array standing in
    # for the call stack a naive `value.each { ... canonicalize(child) ... }`
    # would need one Ruby method-call frame per nesting level for -- the
    # exact same "arbitrarily deep chain of single-child nodes" pathological
    # document `#validate_node`/`RichText::HtmlRenderer#render_node` guard
    # against with a hard `MAX_DEPTH` ceiling. This can't use that same
    # ceiling (see `#digest`'s comment for why truncating past some depth
    # is a correctness bug here, not just a lossy-but-safe fallback), so it
    # has to actually *handle* unbounded depth rather than cap it -- an
    # Array literal living on the heap has no fixed size limit the way
    # Ruby's C call stack does.
    #
    # The stack holds two kinds of work items, popped and processed one at
    # a time until empty: `[:value, x]` ("canonicalize x next") and
    # `[:literal, s]` ("write s to `sha` verbatim next") -- expanding a Hash
    # or Array pushes a whole run of both kinds (`{`, each key/colon/value/
    # comma, `}`) in one go. Since `stack.pop` takes from the *end*, and
    # this needs to process a run of ops in the order they were conceived
    # (open brace first, close brace last), each run is pushed
    # *reversed* (`ops.reverse`) so the first-conceived op ends up on top.
    # A nested Hash/Array's own `[:value, ...]` op sits at exactly the
    # right position in that pushed run -- when it's popped and expands
    # into its own run, that run lands on top of (and so is fully drained
    # before) whatever this level had left to do, which is standard
    # iterative pre-order tree traversal.
    def write_canonical(value, sha)
      stack = [ [ :value, value ] ]

      until stack.empty?
        kind, payload = stack.pop

        if kind == :literal
          sha.update(payload)
          next
        end

        case payload
        when Hash
          ops = [ [ :literal, "{" ] ]
          payload.keys.sort.each_with_index do |key, index|
            ops << [ :literal, "," ] if index > 0
            ops << [ :literal, "#{JSON.generate(key.to_s)}:" ]
            ops << [ :value, payload[key] ]
          end
          ops << [ :literal, "}" ]
          stack.concat(ops.reverse)
        when Array
          ops = [ [ :literal, "[" ] ]
          payload.each_with_index do |element, index|
            ops << [ :literal, "," ] if index > 0
            ops << [ :value, element ]
          end
          ops << [ :literal, "]" ]
          stack.concat(ops.reverse)
        else
          sha.update(JSON.generate(payload))
        end
      end
    end

    # A `"text"` node is structurally different from every other node --
    # it carries a literal `"text"` String and an optional `"marks"` array
    # instead of a `"content"` array of children -- so it gets its own
    # branch rather than going through the generic "look the type up in
    # `RichText::Schema`, check its attributes, recurse into `content`"
    # path below. It's still one of the 13 built-in node *names* (so
    # `RichText::Schema.node("text")` exists, for anything that wants to
    # look up its renderer slots in Task 2), but nothing about validating a
    # text node depends on that registration, so this branch never
    # consults it.
    #
    # `path` is a breadcrumb string ("root.content[2].content[0]") used
    # only for the structural errors below -- it has nothing to do with
    # `RichText::Schema` lookups, it just gives a human something to look
    # at when a document has more than one node of the same type. `depth`
    # is the recursion guard (`MAX_DEPTH`, see its comment); every call
    # into a child bumps it by exactly one, so a document that's a long
    # chain of single-child nodes (the pathological case) still terminates
    # instead of recursing until the stack blows.
    #
    # The very first check -- `node.is_a?(Hash)` -- is what makes every
    # other malformed-input case below safe: a `nil` that slipped into a
    # `"content"` array, a bare String or Integer where a node object
    # belongs, all land here (this method is what every content-array
    # element gets recursed into) and become one error message instead of
    # a `NoMethodError`/`TypeError` the moment the code below tries `node["type"]`.
    #
    # `parent` is the enclosing node's `RichText::NodeType` (`nil` at the
    # root) -- whether this node may carry marks at all depends on it
    # (`RichText::NodeType#allows_child_marks?`).
    def validate_node(node, errors, path:, depth:, known:, parent:)
      unless node.is_a?(Hash)
        errors << "node at #{path} is not an object"
        return
      end

      if depth > MAX_DEPTH
        errors << "#{path} exceeds the maximum nesting depth (#{MAX_DEPTH})"
        return
      end

      type_name = node["type"]

      if type_name == "text"
        if !node["text"].is_a?(String)
          errors << "#{path}: a text node needs a String \"text\""
        elsif node["text"].empty?
          errors << "#{path}: a text node can't be empty"
        end
        validate_marks(node, errors, path, known, parent)
        return
      end

      type = RichText::Schema.node(type_name)
      if type.nil?
        errors << "unknown node type #{type_name.inspect}"
      else
        validate_attributes(type, node["attrs"], errors, known)
      end

      validate_marks(node, errors, path, known, parent)
      validate_children(node["content"], errors, path, depth, known, type)
      validate_content_model(type, node["content"], errors, path) if type
    end

    # `type`'s own content expression against the types of `content`'s
    # children (`RichText::ContentExpression#match?`). Skipped when a child
    # is malformed or of an unknown type -- `#validate_children` already
    # reported that child, and "the content doesn't match" on top of it
    # would be noise about the same problem. A type with no `content`
    # declaration is a leaf and takes no children at all.
    def validate_content_model(type, content, errors, path)
      children = content.is_a?(Array) ? content : []
      expression = type.content

      if expression.nil?
        errors << "#{path}: #{type.name} can't have content" unless children.empty?
        return
      end
      return unless content.nil? || content.is_a?(Array)

      child_types = children.map { |child| child.is_a?(Hash) ? RichText::Schema.node(child["type"]) : nil }
      return if child_types.any?(&:nil?)

      errors << "#{path}: #{type.name} content is invalid (expected \"#{expression.source}\")" unless expression.match?(child_types)
    end

    # `content`, when present at all, must be an Array of node objects --
    # deliberately *checked*, not coerced with `Array(...)`: `Array({"a" =>
    # 1})` reshapes a Hash into `[["a", 1]]` instead of raising, which would
    # silently validate something that isn't remotely a list of child
    # nodes rather than reporting the real problem ("content" is the wrong
    # shape entirely).
    def validate_children(content, errors, path, depth, known, parent)
      return if content.nil?

      unless content.is_a?(Array)
        errors << "#{path}.content must be an array"
        return
      end

      content.each_with_index { |child, index| validate_node(child, errors, path: "#{path}.content[#{index}]", depth: depth + 1, known: known, parent: parent) }
    end

    # Same "must be an Array, not coerced" rule as `#validate_children`,
    # applied to a text node's `"marks"`, plus the same `node.is_a?(Hash)`
    # guard per mark entry (a `"marks"` array can just as easily hold a
    # stray non-object as `"content"` can).
    #
    # Runs for any node, not just text (ProseMirror lets an inline node like
    # `hardBreak` carry marks too). Marks are only allowed where the parent
    # holds inline content that admits marks (`RichText::NodeType
    # #allows_child_marks?` -- not on a block, not inside a `codeBlock`),
    # and a set of marks must be one ProseMirror would build: no type twice,
    # no pair where either excludes the other (`RichText::MarkType
    # #excludes?`; `code` excludes everything).
    def validate_marks(node, errors, path, known, parent)
      marks = node["marks"]
      return if marks.nil?

      unless marks.is_a?(Array)
        errors << "#{path}.marks must be an array"
        return
      end
      return if marks.empty?

      errors << "#{path}: marks aren't allowed here" unless parent&.allows_child_marks?
      validate_mark_set(marks, errors, path)

      marks.each_with_index do |mark_data, index|
        mark_path = "#{path}.marks[#{index}]"

        unless mark_data.is_a?(Hash)
          errors << "mark at #{mark_path} is not an object"
          next
        end

        mark_type_name = mark_data["type"]
        mark_type = RichText::Schema.mark(mark_type_name)
        if mark_type.nil?
          errors << "unknown mark type #{mark_type_name.inspect}"
        else
          validate_attributes(mark_type, mark_data["attrs"], errors, known)
        end
      end
    end

    # `attrs` is `nil` for the ordinary "this type declares no attributes,
    # or declares some but the document omits them all" case -- treated as
    # `{}` so the `required` check below still fires. Anything present but
    # not a Hash (an `"attrs"` given as an Array or a String, say) is the
    # same class of malformed-shape problem `#validate_children`/
    # `#validate_marks` guard against, and gets the same treatment: an
    # error message, not a `TypeError` from `attrs[attribute.name.to_s]`.
    def validate_attributes(type, attrs, errors, known)
      attrs = {} if attrs.nil?
      unless attrs.is_a?(Hash)
        errors << "#{type.name}.attrs must be an object"
        return
      end

      type.attributes.each do |attribute|
        value = attrs[attribute.name.to_s]

        if value.nil?
          errors << "#{type.name}.#{attribute.name} is required" if attribute.required
          next
        end

        unless attribute_type_matches?(attribute.type, value)
          errors << "#{type.name}.#{attribute.name} must be a #{attribute.type}"
          next
        end

        errors << "#{type.name}.#{attribute.name} must be one of #{Array(attribute.in).join(", ")}" if attribute.in && !Array(attribute.in).include?(value)
        errors << "#{type.name}.#{attribute.name} format is invalid" if attribute.format && value.is_a?(String) && !value.match?(attribute.format)
        next if attribute.reference && known&.include?(reference_key(type, attribute, value, attrs))

        errors << "#{type.name}.#{attribute.name} is invalid" if attribute.validate && !run_attribute_validation(attribute, value, attrs)
      end
    end

    def validate_mark_set(marks, errors, path)
      types = marks.filter_map { |mark| RichText::Schema.mark(mark["type"]) if mark.is_a?(Hash) }

      types.map(&:name).tally.each { |name, count| errors << "#{path}: mark #{name} appears more than once" if count > 1 }
      types.uniq(&:name).combination(2).each do |a, b|
        errors << "#{path}: marks #{a.name} and #{b.name} can't be combined" if a.excludes?(b) || b.excludes?(a)
      end
    end

    def collect_references(type, attrs, found)
      return unless type && attrs.is_a?(Hash)

      type.attributes.each do |attribute|
        next unless attribute.reference

        value = attrs[attribute.name.to_s]
        found << reference_key(type, attribute, value, attrs) unless value.nil?
      end
    end

    # `reference: true` -> the value alone; `reference: [ :type ]` -> scoped
    # by those sibling attributes' values (`internalLink` page 7 and post 7
    # are different references).
    def reference_key(type, attribute, value, attrs)
      scope = attribute.reference.is_a?(Array) ? attribute.reference.map { |name| attrs[name.to_s] } : []
      [ type.name, attribute.name.to_s, value, *scope ]
    end

    def attribute_type_matches?(type, value)
      case type
      when :string then value.is_a?(String)
      when :integer then value.is_a?(Integer)
      when :boolean then value == true || value == false
      else true
      end
    end

    # `validate:` procs come in two shapes (see `RichText::Schema::Attribute`):
    # the common single-value `->(value) { ... }`, and a two-argument
    # `->(value, attrs) { ... }` for the rare check that needs a sibling
    # attribute -- `internalLink.id`'s existence check depends on whether
    # the sibling `type` attribute says `page` or `post`. Dispatching on
    # `arity` rather than always passing `attrs` keeps every ordinary
    # `validate:` proc exactly as simple as the DSL advertises
    # (`->(value) { ... }`).
    def run_attribute_validation(attribute, value, attrs)
      attribute.validate.arity == 1 ? attribute.validate.call(value) : attribute.validate.call(value, attrs)
    end
  end
end
