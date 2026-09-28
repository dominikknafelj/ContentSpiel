# A value object around one Tiptap/ProseMirror JSON document (design spec
# §3.1) -- what `posts.body`/`content_blocks.body` store per locale, one
# `RichText::Document` per language. Immutable and comparison-friendly on
# purpose: models read one out of the jsonb column, editors and renderers
# read it back through `#to_h`/`#validate`/`#digest`, and nothing needs to
# mutate a document in place (an edit round-trips through the editor and
# writes a whole new Hash back).
#
# `#to_html`/`#to_markdown`/`.from_markdown`/`.from_html` (spec §3.1) arrive
# in Tasks 2/3/5 -- this task only needs enough of the value object for
# storage and validation to exist: `.new`, `.empty`, `#to_h`, `#blank?`,
# `#digest` and `#validate`.
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

    def initialize(hash)
      @hash = hash || EMPTY_HASH.deep_dup
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
    def self.from_markdown(markdown) = RichText::Markdown.load(markdown)

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
    def to_html(locale: I18n.locale, urls: PublicSite::Urls.new)
      context = RichText::RenderContext.new(locale: locale, urls: urls)

      Rails.cache.fetch([ "rich_text", digest, RichText::Schema.version, locale, context.preview ]) do
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
    def validate
      errors = []
      errors << "the document's root node must be \"doc\", got #{@hash["type"].inspect}" unless @hash.is_a?(Hash) && @hash["type"] == "doc"
      validate_node(@hash, errors, path: "root", depth: 0)
      errors
    end

    private

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
    def validate_node(node, errors, path:, depth:)
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
        errors << "#{path}: a text node needs a String \"text\"" unless node["text"].is_a?(String)
        validate_marks(node, errors, path)
        return
      end

      type = RichText::Schema.node(type_name)
      if type.nil?
        errors << "unknown node type #{type_name.inspect}"
      else
        validate_attributes(type, node["attrs"], errors)
      end

      validate_children(node["content"], errors, path, depth)
    end

    # `content`, when present at all, must be an Array of node objects --
    # deliberately *checked*, not coerced with `Array(...)`: `Array({"a" =>
    # 1})` reshapes a Hash into `[["a", 1]]` instead of raising, which would
    # silently validate something that isn't remotely a list of child
    # nodes rather than reporting the real problem ("content" is the wrong
    # shape entirely).
    def validate_children(content, errors, path, depth)
      return if content.nil?

      unless content.is_a?(Array)
        errors << "#{path}.content must be an array"
        return
      end

      content.each_with_index { |child, index| validate_node(child, errors, path: "#{path}.content[#{index}]", depth: depth + 1) }
    end

    # Same "must be an Array, not coerced" rule as `#validate_children`,
    # applied to a text node's `"marks"`, plus the same `node.is_a?(Hash)`
    # guard per mark entry (a `"marks"` array can just as easily hold a
    # stray non-object as `"content"` can).
    def validate_marks(text_node, errors, path)
      marks = text_node["marks"]
      return if marks.nil?

      unless marks.is_a?(Array)
        errors << "#{path}.marks must be an array"
        return
      end

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
          validate_attributes(mark_type, mark_data["attrs"], errors)
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
    def validate_attributes(type, attrs, errors)
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
        errors << "#{type.name}.#{attribute.name} is invalid" if attribute.validate && !run_attribute_validation(attribute, value, attrs)
      end
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
