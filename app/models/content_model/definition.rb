# One registered type (spec §3.1): its label, its declarative field schema,
# which existing columns it edits, and what it's capable of. The schema is
# data, not a class, so admin-defined types (roadmap Phase 3) can feed the
# same format later; `ContentModel::FieldSet` turns it into an ActiveModel
# class.
#
# Subclassed per registry (`BlockTypeDefinition`, `ContentTypeDefinition`,
# `FieldGroupDefinition`) to add the handful of fields specific to that kind
# of type (a rendering component, starter content, a colour slot, ...)
# via `dsl_attribute`.
module ContentModel
  class Definition
    # The scalar types are `ContentModel::FieldTypes`' (each with its cast,
    # its option rules, its validation, whether it is translatable and how
    # it is audited); the group types nest a field group and are this
    # class's and `FieldSet`'s own.
    GROUP_TYPES = %i[group groups].freeze
    # `blank:` is the label of a select's (or a content type field's) empty choice ("Plain text", "All types"); without
    # it the choice has no label. `max:` counts characters for a `:code` field
    # and is a number's upper bound for an `:integer`.
    #
    # `label:` is what CS Studio calls the field where the name humanised
    # would read wrong ("File name" for `filename`): a literal in the type's
    # definition, as a type's own label and a select's choices are. Everything
    # that names a field to a person asks `Field#label`, never the name: the
    # input's label, a translation tab's shared fields, a group's rows on the
    # public page, and a validation message (`ContentBlock` and `Post`
    # `.human_attribute_name`).
    #
    # `control:` is how CS Studio draws a field where its type's default
    # control is wrong for it: `:segmented` draws a `:select`'s choices as a
    # row of buttons (radios underneath, so it works from the keyboard and
    # without a script; note block spec, decision 7). It is a look and changes
    # nothing about the value or its validation.
    #
    # `help:` is a line under a string or a text field in CS Studio (the Note
    # block's title: what an empty one does; the Diagram block's
    # description), and `placeholder_from:` names a select declared BEFORE
    # the string whose chosen label is the string's placeholder (the Note
    # block's title shows the kind's word, design answer B3). Both are literals of the type's definition, as `label:` is.
    # `max:` on a string counts characters, as on a code field.
    #
    # `format:` is the shape a string must have (a Regexp, tested against the whole
    # cast value; a blank value has none to test) and `format_message:` the I18n
    # key of the sentence that refuses it. The sentence is the whole message only
    # where the model's locale entry for the field says `format: "%{message}"`
    # (the anchor's, `activerecord.errors.models.content_block/settings`); without
    # one it reads after the field's label.
    #
    # `translation_required:` is the image alt's rule for a translated field:
    # blank in a target language, it reads missing there when the primary
    # language's value is present (`Translations::Status`), and is never
    # required for a save. It needs `translated: true`.
    #
    # `drawing:` names the `:diagram_drawing` field a `:mermaid` source's
    # drawing is written into (`ContentModel::FieldTypes`, checked once every
    # field is declared).
    OPTIONS = %i[required default min max translated translation_required options of blank label control help placeholder_from format format_message drawing].freeze
    CONTROLS = %i[segmented].freeze

    # One field in the schema: `options` carries everything but name/type
    # (`required:`, `default:`, `min:`/`max:`, `translated:`, `options:` for
    # `select`, `of:` for a `group`/`groups`). Kept as a plain `Data` (not a
    # full class) because the schema itself is meant to be inert data -- see
    # the class comment -- and these three predicates are the only
    # behaviour callers need off a field, with the name a person reads (`label`).
    Field = Data.define(:name, :type, :options) do
      def translated? = options[:translated] == true
      def required? = options[:required] == true
      def translation_required? = options[:translation_required] == true
      def group? = GROUP_TYPES.include?(type)
      # Of a type only a built-in block type may declare (`FieldTypes::BLOCK_ONLY`).
      def block_only? = FieldTypes::BLOCK_ONLY.include?(type)
      def label = options[:label].presence || name.humanize
      # The line under the field in CS Studio, or nil.
      def help = options[:help].presence
      # Drawn as a row of buttons (`control: :segmented`), not a <select>;
      # the option is refused on any type but a select (`FieldTypes`).
      def segmented? = options[:control] == :segmented
      # The scalar type's entry in `ContentModel::FieldTypes`, nil for a group.
      def field_type = FieldTypes.find(type)
    end

    attr_reader :name, :fields, :uses_columns

    def initialize(name)
      @name = name
      @label = name.humanize
      @fields = []
      @uses_columns = []
      @capabilities = []
    end

    # Defines a method that both sets and reads one value: called with an
    # argument during registration (`t.label "Event"`), with none to read it
    # back (a rendering loop calling `definition.component`). Collapses what
    # would otherwise be a `label`/`component`/`list_component`/
    # `detail_component`-shaped method on every subclass into one macro.
    def self.dsl_attribute(name)
      ivar = :"@#{name}"
      define_method(name) do |value = nil|
        value.nil? ? instance_variable_get(ivar) : instance_variable_set(ivar, value)
      end
    end

    dsl_attribute :label

    # The checks every field shares are here; what a type refuses of its
    # declaration is the type's own (`FieldType#options`), handed the fields
    # declared before this one.
    def field(name, type, **options)
      scalar = FieldTypes.find(type)
      raise ArgumentError, "unknown field type #{type.inspect}" unless scalar || GROUP_TYPES.include?(type)
      raise ArgumentError, "unknown field option(s) #{(options.keys - OPTIONS).inspect}" if (options.keys - OPTIONS).any?
      raise ArgumentError, "#{type} fields need `of:` naming a field group" if GROUP_TYPES.include?(type) && options[:of].blank?
      raise ArgumentError, "#{type} fields can't have a default (there's no one canonical default for a nested value)" if GROUP_TYPES.include?(type) && options.key?(:default)
      raise ArgumentError, "`label:` is the field's name as a person reads it, a string" if options.key?(:label) && !(options[:label].is_a?(String) && options[:label].present?)
      if options.key?(:translation_required) && !(options[:translation_required] == true && options[:translated] == true)
        raise ArgumentError, "`translation_required: true` is for a field that is also `translated: true`"
      end
      refuse_type!(type)
      scalar ? scalar.options.call(options, @fields) : FieldTypes.refuse_choice_and_string_options(options)

      @fields << Field.new(name: name.to_s, type: type, options: options)
    end

    # Hook for a kind of definition that takes only some of the types
    # (`FieldTypes::BLOCK_ONLY`); raises `ArgumentError`.
    def refuse_type!(_type); end
    private :refuse_type!

    # Each field type's refusals that need every field declared
    # (`FieldType#finish`): called by `ContentModel::Registry#register`
    # before `finalize!`.
    def finish_fields!
      fields.each { |field| field.field_type&.finish&.call(field, fields) }
    end

    def uses(*columns) = @uses_columns.concat(columns.map(&:to_s))
    def capability(*names) = @capabilities.concat(names)
    def capability?(name) = @capabilities.include?(name)
    def capabilities = @capabilities.dup

    def field_set = FieldSet.for(self)

    # Hook for subclasses to check the finished definition once
    # registration's block has run (called by `ContentModel::Registry
    # #register` before the definition is stored) -- e.g.
    # `FieldGroupDefinition` rejects nested group fields here, since that's
    # only knowable once all `field` calls are in.
    def finalize!; end
  end
end
