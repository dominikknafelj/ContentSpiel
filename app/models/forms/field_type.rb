module Forms
  # One kind of form field, as `Forms::FieldTypes` holds it: the half of a
  # visitor's form field that the content model does not have.
  #
  # What a value IS (its cast, its validation, whether it is text) stays
  # `ContentModel::FieldTypes`', named by `value_type`; the form adds only
  # what a visitor's form needs. Folding the two later would be one member
  # each (forms plan, decision 2).
  #
  # - `name`: a String, `"short_text"` for a built-in and `"owner/name"` for
  #   a gem's (`ContentSpiel::Plugins.form_field_types`).
  # - `value_type`: a registered `ContentModel::FieldTypes` name.
  # - `label`: the builder's word for the type, a literal as a block type's.
  # - `options`: which of `:choices` and `:display` the builder offers.
  # - `max_length`: characters, a positive Integer, or nil.
  # - `summary`: whether the submissions list may show this answer.
  # - `input`: the public component, `(field:, value:, error:)`.
  # - `display`: `->(value, field, locale:) { String }`, how a value reads
  #   where it is not edited (a submission).
  FieldType = Data.define(:name, :value_type, :label, :options, :max_length, :summary, :input, :display)

  class FieldType
    OPTIONS = %i[choices display].freeze

    def initialize(name:, value_type:, label:, options:, max_length:, summary:, input:, display:)
      raise ArgumentError, "a form field type is named by a String, not #{name.inspect}" unless name.is_a?(String) && name.present?
      raise ArgumentError, "#{name}: value_type #{value_type.inspect} is not a registered ContentModel field type (known: #{ContentModel::FieldTypes.names.join(", ")})" unless ContentModel::FieldTypes.find(value_type)
      raise ArgumentError, "#{name}: label is the builder's word for the type, a String" unless label.is_a?(String) && label.present?
      raise ArgumentError, "#{name}: options is a list of #{OPTIONS.map(&:inspect).join(" and ")}" unless options.is_a?(Array) && (options - OPTIONS).empty?
      raise ArgumentError, "#{name}: max_length is a positive Integer or nil" unless max_length.nil? || (max_length.is_a?(Integer) && max_length.positive?)
      raise ArgumentError, "#{name}: summary is true or false" unless [ true, false ].include?(summary)
      raise ArgumentError, "#{name}: input is a Blocks::FormFields::Base component class" unless input.is_a?(Class) && input <= Blocks::FormFields::Base
      raise ArgumentError, "#{name}: display is a callable taking (value, field, locale:)" unless display.respond_to?(:call)

      super
    end
  end
end
