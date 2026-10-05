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
    #
    # `reference` (Task 7 fix round 1, I2) marks an attribute whose
    # `validate` is an *existence* check against another record -- the
    # `Media::Asset` behind `image.asset_id`, the page/post behind
    # `internalLink.id`. `true` means the value alone names the record;
    # an Array of sibling attribute names means those siblings scope it
    # (`internalLink.id` is scoped by `type`). Such a check only blocks a
    # reference that's *new*: `RichText::Document#validate(known_references:)`
    # skips it for a reference the stored document already had, so a
    # target deleted after the fact never makes the document unsaveable.
    # See `RichText::Document#references`.
    Attribute = Data.define(:name, :type, :required, :in, :format, :validate, :reference)

    # One directive attribute mapping (`TypeDefinition#directive`'s
    # `**mapping`) -- `node_attr` is the node's own `attribute` name the
    # directive's `key="value"` pair feeds (not necessarily the same name
    # as the directive key itself -- `image`'s `asset` directive attribute
    # names the node's `asset_id`), `type` is the coercion to apply to the
    # directive's raw String value (`:string` is the identity; `:integer`
    # parses it, per `TypeDefinition#coerce_directive_value`).
    DirectiveAttribute = Data.define(:node_attr, :type)

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

      # `attribute(name, type = :string, required: false, in: nil, format: nil, validate: nil, reference: nil)`
      # (design spec §3.2). `type` is one of `:string`/`:integer`/`:boolean`
      # -- just enough to catch "level" being sent as a string, or `alt`
      # being sent as a number -- validated generically by
      # `RichText::Document`, not enforced here at registration time.
      def attribute(name, type = :string, required: false, in: nil, format: nil, validate: nil, reference: nil)
        # `in` is a Ruby keyword (pattern matching, `for x in y`), so it
        # parses fine as a keyword-argument *label* above but not as a bare
        # expression below -- `binding.local_variable_get` is the
        # documented way to read a local variable whose name shadows a
        # keyword.
        allowed_values = binding.local_variable_get(:in)
        @attributes << Attribute.new(name: name.to_sym, type: type, required: required, in: allowed_values, format: format, validate: validate, reference: reference)
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

      # Unused -- reserved for a future Markdown parser hook distinct from
      # `#directive`'s own (every directive-bearing built-in parses through
      # `RichText::Markdown::Loader#build_directive`/`#attrs_from_directive`
      # below instead, driven by the schema rather than a per-type block).
      def markdown_in(&block) = block ? (@markdown_in = block) : @markdown_in

      # `directive(name, **mapping)` (design spec §3.4) -- records the
      # `::name{...}` keyword this type answers to in Markdown, plus how
      # each directive attribute (a `key="value"` pair, always a raw
      # String) maps onto this type's own `attribute` declarations. A
      # mapping value of `:string`/`:integer` means "the directive key *is*
      # the node attribute name, coerced to that type"; `{ attr: :other,
      # type: :integer }` remaps the key too -- `image`'s `asset` directive
      # attribute names the node's `asset_id`, not `asset`.
      #
      # `RichText::Schema.directive_node` finds a type by this name (fed
      # into `RichText::Markdown::Loader#build_directive`), and
      # `#attrs_from_directive`/`#directive_markdown` below are this
      # declaration's read and write halves -- one declaration drives both
      # the parser and the writer, so a plugin's directive node type only
      # has to state this mapping once, not keep the two in sync by hand
      # the way `youtube`/`image` used to (a hardcoded `case name when
      # "youtube" ... when "image" ...` in the Loader, and a bespoke
      # `render_youtube_directive`/`render_image_directive` per node in
      # `RichText::BuiltIns`).
      def directive(name = nil, **mapping)
        return @directive unless name

        @directive = name.to_s
        @directive_attributes = mapping.each_with_object({}) do |(key, spec), hash|
          node_attr, type = spec.is_a?(Hash) ? [ spec.fetch(:attr, key), spec.fetch(:type, :string) ] : [ key, spec ]
          hash[key.to_s] = DirectiveAttribute.new(node_attr: node_attr.to_sym, type: type)
        end
        @directive
      end

      def directive_attributes = @directive_attributes || {}

      # Builds this type's `"attrs"` Hash from a directive's raw
      # `key="value"` String attributes (already unescaped) --
      # `RichText::Markdown::Loader#build_directive`'s other half. A
      # directive key this type never mapped is ignored; a mapped key the
      # directive didn't supply is left out of the result entirely (not
      # set to `nil`) so an optional attribute genuinely absent from the
      # directive stays genuinely absent from the node, matching what
      # `RichText::Markdown::Dumper` would itself have produced.
      def attrs_from_directive(raw_attrs)
        directive_attributes.each_with_object({}) do |(key, spec), attrs|
          next unless raw_attrs.key?(key)

          attrs[spec.node_attr.to_s] = coerce_directive_value(raw_attrs[key], spec.type)
        end
      end

      # The Markdown directive line for `node` -- `#attrs_from_directive`'s
      # other half, called from this type's own `markdown_out` block
      # (`RichText::BuiltIns`). Emits one `key="value"` pair per declared
      # directive attribute whose value is present, plus any that are
      # `blank?` but back a `required:` node `attribute` anyway (rendered,
      # rather than silently vanishing from the directive line -- a
      # required attribute being blank only happens on a document that
      # skipped `#validate`, the same "hostile documents render inert, not
      # broken" posture every other `html`/`markdown_out` block here takes).
      def directive_markdown(node)
        attrs = node["attrs"].is_a?(Hash) ? node["attrs"] : {}
        parts = directive_attributes.filter_map do |key, spec|
          value = attrs[spec.node_attr.to_s]
          next if value.blank? && !find_attribute(spec.node_attr)&.required

          %(#{key}="#{RichText::Markdown.escape_directive_attr(value)}")
        end
        "::#{@directive}{#{parts.join(" ")}}"
      end

      private

      def coerce_directive_value(value, type)
        type == :integer ? Integer(value, exception: false) : value
      end
    end

    class << self
      def register_node(name, &block) = register(:node, name, &block)
      def register_mark(name, &block) = register(:mark, name, &block)

      def node(name) = nodes[name.to_s]
      def mark(name) = marks[name.to_s]

      # Finds the registered node type that answers to Markdown directive
      # `name` (`::name{...}`) -- only nodes declare a `directive` (a mark
      # has no standalone Markdown line of its own to answer to), so this
      # only ever searches `nodes`, not `marks`. `RichText::Markdown::Loader
      # #build_directive` is the only caller; dispatching this way --
      # asking the schema "who owns this directive name" -- rather than a
      # hardcoded `case name when "youtube" ... when "image" ...` is what
      # lets a plugin's own directive node type be found exactly the way a
      # built-in's is (design spec §3.4, review round 1's I6).
      def directive_node(name) = nodes.values.find { |type| type.directive == name.to_s }

      # The position `name` registered in (`RichText::Schema.register_mark`
      # call order), or `nil` for an unregistered name -- `RichText
      # ::Document#normalized`/`RichText::Markdown::Loader#text_node`'s
      # shared notion of "canonical mark order" (review round 1's I7):
      # Tiptap/ProseMirror already keeps an editor-built document's marks
      # in schema order, so this is what "already canonical" means for a
      # mark array, and what both the digest-adjacent `#normalized` and the
      # Markdown loader canonicalize *into*.
      def mark_order(name) = marks.keys.index(name.to_s)

      def reset!
        @nodes = {}
        @marks = {}
        @version = nil
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
      #
      # Kept until the registry changes (`register`, `reset!`): every
      # `Document#to_html` reads it for its cache key, cache hit or not, and
      # it is a JSON dump and a SHA of the whole schema. A type's shape is
      # set inside its registration block, before it enters the registry, so
      # nothing changes it behind the memo.
      def version
        @version ||= Digest::SHA256.hexdigest(JSON.generate(
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
        # After the type is in: cleared first, a `version` read from another
        # thread in between would memoise the schema without it.
        @version = nil
        type
      end

      # The content model (`group`/`content` on a node, `excludes` on a
      # mark -- final fix wave, A) is part of a type's shape too.
      def signature_for(registry)
        registry.sort.map { |name, type| [ name, type.attributes.map { |attribute| attribute_signature(attribute) }, content_model_signature(type) ] }
      end

      def content_model_signature(type)
        type.is_a?(RichText::NodeType) ? [ type.group, type.content&.source, type.allows_child_marks? ] : [ type.excludes ]
      end

      def attribute_signature(attribute)
        [ attribute.name.to_s, attribute.type.to_s, attribute.required, Array(attribute.in), attribute.format&.source ]
      end

      def nodes = (@nodes ||= {})
      def marks = (@marks ||= {})
    end
  end
end
