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
    # `:code` is source code: stored as typed (`FieldSet#cast_code`), never
    # stripped like `:text`, and never translated -- the code is the same in
    # every language, and a translated field is what is offered to an AI
    # provider (`Admin::Ui::FieldComponent::TRANSLATABLE_TYPES` does not list
    # it either).
    SCALAR_TYPES = %i[string text code integer boolean date url select content_type tag].freeze
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
    # `help:` is a line under a string field in CS Studio (the Note block's
    # title: what an empty one does), and `placeholder_from:` names a select
    # declared BEFORE the string whose chosen label is the string's
    # placeholder (the Note block's title shows the kind's word, design
    # answer B3). Both are literals of the type's definition, as `label:` is.
    # `max:` on a string counts characters, as on a code field.
    OPTIONS = %i[required default min max translated options of blank label control help placeholder_from].freeze
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
      def group? = GROUP_TYPES.include?(type)
      def label = options[:label].presence || name.humanize
      # The line under the field in CS Studio, or nil.
      def help = options[:help].presence
      # Drawn as a row of buttons (`control: :segmented`), not a <select>.
      def segmented? = type == :select && options[:control] == :segmented
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

    def field(name, type, **options)
      raise ArgumentError, "unknown field type #{type.inspect}" unless (SCALAR_TYPES + GROUP_TYPES).include?(type)
      raise ArgumentError, "unknown field option(s) #{(options.keys - OPTIONS).inspect}" if (options.keys - OPTIONS).any?
      raise ArgumentError, "#{type} fields need `of:` naming a field group" if GROUP_TYPES.include?(type) && options[:of].blank?
      raise ArgumentError, "#{type} fields can't have a default (there's no one canonical default for a nested value)" if GROUP_TYPES.include?(type) && options.key?(:default)
      raise ArgumentError, "select fields need `options:`" if type == :select && options[:options].blank?
      raise ArgumentError, "code fields can't be translated (the code is the same in every language)" if type == :code && options[:translated]
      raise ArgumentError, "`label:` is the field's name as a person reads it, a string" if options.key?(:label) && !(options[:label].is_a?(String) && options[:label].present?)
      raise ArgumentError, "`blank:` names the empty choice of a select that isn't required" if options.key?(:blank) && (!%i[select content_type].include?(type) || options[:required])
      if options.key?(:control)
        raise ArgumentError, "`control:` is one of #{CONTROLS.map(&:inspect).join(", ")}" unless CONTROLS.include?(options[:control])
        raise ArgumentError, "`control: :segmented` draws a select's choices as buttons: it is for a select" unless type == :select
        raise ArgumentError, "`control: :segmented` has no button for a select's empty choice: it is for a select without `blank:`" if options.key?(:blank)
      end
      raise ArgumentError, "`help:` is a line under a string field, written as a String" if options.key?(:help) && !(type == :string && options[:help].is_a?(String) && options[:help].strip != "")
      if options.key?(:placeholder_from)
        source = @fields.find { |candidate| candidate.name == options[:placeholder_from].to_s }
        raise ArgumentError, "`placeholder_from:` is for a string field and names a select field declared before it" unless type == :string && source&.type == :select
      end
      raise ArgumentError, "`max:` on a string field is a number of characters, a positive Integer" if type == :string && options.key?(:max) && !(options[:max].is_a?(Integer) && options[:max].positive?)

      @fields << Field.new(name: name.to_s, type: type, options: options)
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
