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

    def self.empty = new(EMPTY_HASH.deep_dup)

    def initialize(hash)
      @hash = hash || EMPTY_HASH.deep_dup
    end

    def to_h = @hash

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
    def validate
      errors = []
      errors << "the document's root node must be \"doc\", got #{@hash["type"].inspect}" unless @hash["type"] == "doc"
      validate_node(@hash, errors)
      errors
    end

    private

    def content?(node)
      return false if node.nil?

      case node["type"]
      when "text" then node["text"].present?
      when "image", "youtube" then true
      else Array(node["content"]).any? { |child| content?(child) }
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
    def validate_node(node, errors)
      type_name = node["type"]

      if type_name == "text"
        errors << "a text node needs a String \"text\"" unless node["text"].is_a?(String)
        validate_marks(node, errors)
        return
      end

      type = RichText::Schema.node(type_name)
      if type.nil?
        errors << "unknown node type #{type_name.inspect}"
      else
        validate_attributes(type, node["attrs"] || {}, errors)
      end

      Array(node["content"]).each { |child| validate_node(child, errors) }
    end

    def validate_marks(text_node, errors)
      Array(text_node["marks"]).each do |mark_data|
        mark_type_name = mark_data["type"]
        mark_type = RichText::Schema.mark(mark_type_name)
        if mark_type.nil?
          errors << "unknown mark type #{mark_type_name.inspect}"
        else
          validate_attributes(mark_type, mark_data["attrs"] || {}, errors)
        end
      end
    end

    def validate_attributes(type, attrs, errors)
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
