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
    SCALAR_TYPES = %i[string text integer boolean date url select content_type tag].freeze
    GROUP_TYPES = %i[group groups].freeze
    OPTIONS = %i[required default min max translated options of].freeze

    # One field in the schema: `options` carries everything but name/type
    # (`required:`, `default:`, `min:`/`max:`, `translated:`, `options:` for
    # `select`, `of:` for a `group`/`groups`). Kept as a plain `Data` (not a
    # full class) because the schema itself is meant to be inert data -- see
    # the class comment -- and these three predicates are the only
    # behaviour callers need off a field.
    Field = Data.define(:name, :type, :options) do
      def translated? = options[:translated] == true
      def required? = options[:required] == true
      def group? = GROUP_TYPES.include?(type)
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

      @fields << Field.new(name: name.to_s, type: type, options: options)
    end

    def uses(*columns) = @uses_columns.concat(columns.map(&:to_s))
    def capability(*names) = @capabilities.concat(names)
    def capability?(name) = @capabilities.include?(name)

    def field_set = FieldSet.for(self)

    # Hook for subclasses to check the finished definition once
    # registration's block has run (called by `ContentModel::Registry
    # #register` before the definition is stored) -- e.g.
    # `FieldGroupDefinition` rejects nested group fields here, since that's
    # only knowable once all `field` calls are in.
    def finalize!; end
  end
end
