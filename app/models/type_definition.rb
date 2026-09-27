# One registered type (spec §3.1): its label, its declarative field schema,
# which existing columns it edits, and what it's capable of. The schema is
# data, not a class, so admin-defined types (roadmap Phase 3) can feed the
# same format later; FieldSet turns it into an ActiveModel class.
#
# Subclassed per registry (`BlockTypeDefinition`, `ContentTypeDefinition`,
# `ComponentDefinition`) to add the handful of fields specific to that kind
# of type (a rendering component, starter content, a mind-graph colour, ...).
class TypeDefinition
  SCALAR_TYPES = %i[string text integer boolean date url select content_type tag].freeze
  GROUP_TYPES = %i[component components].freeze
  OPTIONS = %i[required default min max translated options of].freeze

  # One field in the schema: `options` carries everything but name/type
  # (`required:`, `default:`, `min:`/`max:`, `translated:`, `options:` for
  # `select`, `of:` for a group). Kept as a plain `Data` (not a full class)
  # because the schema itself is meant to be inert data -- see the class
  # comment -- and these three predicates are the only behaviour callers need
  # off a field.
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

  # Reader/writer pattern used throughout the DSL (also `component`,
  # `color`, `list_component`, ...): called with an argument to set, without
  # one to read -- lets the registration block read a value it just set a
  # few lines above, and keeps the DSL free of a separate `label=`.
  def label(value = nil)
    value.nil? ? @label : (@label = value)
  end

  def field(name, type, **options)
    raise ArgumentError, "unknown field type #{type.inspect}" unless (SCALAR_TYPES + GROUP_TYPES).include?(type)
    raise ArgumentError, "unknown field option(s) #{(options.keys - OPTIONS).inspect}" if (options.keys - OPTIONS).any?
    raise ArgumentError, "#{type} fields need `of:` naming a component" if GROUP_TYPES.include?(type) && options[:of].blank?
    raise ArgumentError, "select fields need `options:`" if type == :select && options[:options].blank?

    @fields << Field.new(name: name.to_s, type: type, options: options)
  end

  def uses(*columns) = @uses_columns.concat(columns.map(&:to_s))
  def capability(*names) = @capabilities.concat(names)
  def capability?(name) = @capabilities.include?(name)

  def field_set = FieldSet.for(self)

  # Hook for subclasses to check the finished definition once registration's
  # block has run (`TypeRegistry#register` calls this before storing the
  # definition) -- e.g. `ComponentDefinition` rejects nested component
  # fields here, since that's only knowable once all `field` calls are in.
  def finalize!; end
end
