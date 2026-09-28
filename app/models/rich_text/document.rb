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

    def to_h = @hash

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
    # "did this locale's document actually change" checks. `JSON.generate`
    # of a *key-sorted* deep copy, not of `@hash` directly: Ruby Hashes
    # preserve insertion order, so two documents that are semantically
    # identical but built up in a different order (e.g. attrs written
    # `{"level" => 2, "textAlign" => nil}` vs. the reverse) would otherwise
    # digest differently. Array element order is left alone -- `"content"`
    # order is meaningful (it's the document's reading order), unlike Hash
    # key order.
    def digest = Digest::SHA256.hexdigest(JSON.generate(canonicalize(@hash)))

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

    def canonicalize(value)
      case value
      when Hash then value.keys.sort.index_with { |key| canonicalize(value[key]) }
      when Array then value.map { |element| canonicalize(element) }
      else value
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
