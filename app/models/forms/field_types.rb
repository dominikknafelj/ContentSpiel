module Forms
  # The registry of form field types (`Forms::FieldType`). Reset and filled
  # in `config/initializers/types.rb`, after `ContentModel::FieldTypes` (a
  # type names its value type, which must be registered) and before the
  # block types; a gem's types are replayed after the built-ins
  # (`ContentSpiel::Plugins.form_field_types`).
  module FieldTypes
    class << self
      def register(type)
        raise ArgumentError, "a form field type is a Forms::FieldType, not #{type.inspect}" unless type.is_a?(FieldType)
        raise ArgumentError, "the form field type #{type.name.inspect} is already registered" if types.key?(type.name)

        types[type.name] = type
      end

      def find(name) = types[name.to_s]

      def fetch(name)
        find(name) or raise KeyError, "unknown form field type #{name.inspect} (known: #{names.join(", ")})"
      end

      def names = types.keys

      def all = types.values

      def reset! = types.clear

      # The five built-ins, in this order (it is `names`' order).
      def register_built_ins = BuiltInFieldTypes.all.each { |type| register(type) }

      private

      def types = (@types ||= {})
    end
  end
end
