# The registry of Tiptap/ProseMirror node and mark types (design spec §3.2)
# that `RichText::Document#validate` and, from Task 2 on, the HTML and
# Markdown renderers walk. Built-ins register here from
# `config/initializers/types.rb`'s `to_prepare` block, after a `reset!`;
# plugins will call the same `register_node`/`register_mark` later, under a
# prefixed `owner/name`.
#
# This mirrors `ContentModel::Registry` (open-types spec §3.2) in spirit --
# register/fetch-by-name/reset!, a duplicate raises, a malformed name is
# rejected -- but doesn't `extend` it: that mixin manages exactly one
# name => definition map per host module, and a schema needs *two*
# independent ones (nodes and marks share nothing structurally -- a node
# nests inside another node's "content" array, a mark decorates a "text"
# node's "marks" array), under names shaped differently from
# `ContentModel::Registry::NAME_FORMAT` (Tiptap's own built-ins are
# camelCase -- `bulletList`, `horizontalRule` -- not `snake_case`). Rewriting
# the handful of lines that mixin saves, twice, was less code and less
# indirection than bending it to fit two registries.
module RichText
  module Schema
    # Bare camelCase names (`bulletList`, `internalLink`) are reserved for
    # built-ins, matching Tiptap's own node-name casing. Every other name
    # (plugins, later admin-defined node types) must be prefixed with its
    # owner, e.g. `gallery/carousel` -- one `/`, a camelCase-shaped segment
    # on each side. As with `ContentModel::Registry::NAME_FORMAT`, this only
    # checks the *shape* of a name; enforcing that plugins actually prefix
    # themselves is the plugin DSL's job, out of scope here.
    NAME_FORMAT = /\A[a-z][A-Za-z0-9]*(\/[a-z][A-Za-z0-9_]*)?\z/

    # One declared attribute rule on a node or mark type (`attribute` below).
    # `in`/`format`/`validate` are all optional and independent -- a type can
    # combine them (`youtube.id` uses `format`; `internalLink.id` uses only
    # `validate`, since "does this id exist" isn't expressible as a
    # format/range check).
    #
    # `validate` is a proc of arity 1 (`->(value) { ... }`, per the type DSL)
    # *or* arity 2 (`->(value, attrs) { ... }`). The two-argument form exists
    # solely for cross-attribute checks like `internalLink`'s: whether `id`
    # names an existing record depends on the sibling `type` attribute
    # (`page` vs. `post`), which a single-value signature can't see. See
    # `RichText::Document#run_attribute_validation`, the one place that
    # distinguishes the two by arity.
    Attribute = Data.define(:name, :type, :required, :in, :format, :validate)

    # Mixed into both `NodeType` and `MarkType` (via `include`, not
    # duplicated into each file): a node and a mark register through the
    # exact same tiny DSL -- `attribute`, plus renderer slots for HTML and
    # Markdown output that Tasks 2/3 fill in -- and only differ in how
    # `RichText::Document` walks them afterwards. `html`/`markdown_out`/
    # `markdown_in` all follow the same "block sets it, no block reads it
    # back" shape as `ContentModel::Definition.dsl_attribute`, just for a
    # stored Proc instead of a stored value.
    module TypeDefinition
      attr_reader :name, :attributes

      def initialize(name)
        @name = name
        @attributes = []
      end

      # `attribute(name, type = :string, required: false, in: nil, format: nil, validate: nil)`
      # (design spec §3.2). `type` is one of `:string`/`:integer`/`:boolean`
      # -- just enough to catch "level" being sent as a string, or `alt`
      # being sent as a number -- validated generically by
      # `RichText::Document`, not enforced here at registration time.
      def attribute(name, type = :string, required: false, in: nil, format: nil, validate: nil)
        # `in` is a Ruby keyword (pattern matching, `for x in y`), so it
        # parses fine as a keyword-argument *label* above but not as a bare
        # expression below -- `binding.local_variable_get` is the
        # documented way to read a local variable whose name shadows a
        # keyword.
        allowed_values = binding.local_variable_get(:in)
        @attributes << Attribute.new(name: name.to_sym, type: type, required: required, in: allowed_values, format: format, validate: validate)
      end

      def find_attribute(name) = @attributes.find { |attribute| attribute.name == name.to_sym }

      # `html { |node, children, ctx| ... }` -- the renderer Task 2's
      # `RichText::HtmlRenderer` calls for this type, receiving the raw
      # node Hash, its already-rendered children, and a context carrying
      # `locale`/`urls`/`preview`. Every built-in registers one in
      # `RichText::BuiltIns` (Task 1), but the block itself just raises
      # `NotImplementedError` until Task 2 writes the real renderers --
      # what Task 1 needs to prove is that every built-in *has* a slot to
      # fill, not what fills it.
      def html(&block) = block ? (@html = block) : @html

      # `markdown_out { |node, children, ctx| ... }` -- Task 3's Markdown
      # writer, same placeholder story as `html` above.
      def markdown_out(&block) = block ? (@markdown_out = block) : @markdown_out

      # Reserved for Task 3's Markdown *parser* (CommonMark for standard
      # types; a `::name{...}` directive for custom ones). `directive`
      # records which directive keyword a type answers to
      # (`directive "youtube"`) so the parser can look a directive name up
      # against the schema instead of hardcoding "youtube and image are
      # special"; `markdown_in` itself isn't called by anything until
      # Task 3, but the slot is declared now so every built-in's
      # registration block doesn't need reshaping later.
      def markdown_in(&block) = block ? (@markdown_in = block) : @markdown_in
      def directive(name = nil) = name ? (@directive = name.to_s) : @directive
    end

    class << self
      def register_node(name, &block) = register(:node, name, &block)
      def register_mark(name, &block) = register(:mark, name, &block)

      def node(name) = nodes[name.to_s]
      def mark(name) = marks[name.to_s]

      def reset!
        @nodes = {}
        @marks = {}
      end

      # A digest of every registered name plus its attribute *specs*
      # (name/type/required/in/format -- deliberately not the `html`/
      # `markdown_out`/`validate` Procs, which have no stable, serializable
      # identity across a code reload: two loads of the exact same source
      # produce different `Proc` objects, so hashing them in would make
      # `version` change spuriously on every `to_prepare` run instead of
      # only when a type's registered *shape* actually changes). This feeds
      # the HTML render cache key (design spec §3.3) -- it needs to change
      # whenever a type's rendering-relevant shape changes, not on every
      # boot.
      def version
        Digest::SHA256.hexdigest(JSON.generate(
          "nodes" => signature_for(nodes),
          "marks" => signature_for(marks)
        ))
      end

      private

      def register(kind, name, &block)
        name = name.to_s
        raise ArgumentError, "#{name.inspect} isn't a valid #{kind} name (expected camelCaseWord or owner/camelCaseWord)" unless name.match?(NAME_FORMAT)

        registry = kind == :node ? nodes : marks
        raise RichText::DuplicateType, "#{name.inspect} is already a registered #{kind}" if registry.key?(name)

        type = (kind == :node ? RichText::NodeType : RichText::MarkType).new(name)
        block&.call(type)
        registry[name] = type
      end

      def signature_for(registry)
        registry.sort.map { |name, type| [ name, type.attributes.map { |attribute| attribute_signature(attribute) } ] }
      end

      def attribute_signature(attribute)
        [ attribute.name.to_s, attribute.type.to_s, attribute.required, Array(attribute.in), attribute.format&.source ]
      end

      def nodes = (@nodes ||= {})
      def marks = (@marks ||= {})
    end
  end
end
