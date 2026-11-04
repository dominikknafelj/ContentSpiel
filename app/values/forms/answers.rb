module Forms
  # A visitor's answers, cleaned against the form's fields: what to store,
  # what is wrong, and what to draw again.
  #
  # `values` is the stored shape, one row per field in the form's order:
  # `{ "key", "type", "label", "value", "display" }`. The label and the
  # display are the DEFAULT language's, whatever language the visitor sent in
  # and whatever the form says later: an editor reads a submission, and a
  # later edit of the form (a label, a choice reworded) changes no old one.
  # `errors` is `{ key => :blank | :invalid | :inclusion | :too_long }`.
  # `typed` is `{ key => String }` as the visitor typed it, for a redraw.
  #
  # A key the form does not have is ignored, and a value that is not a String
  # (a list or a hash sent for a field) is no answer. The value's cast and
  # validation are the content model's (`Forms::Field#definition_field`).
  module Answers
    Result = Data.define(:values, :errors, :typed)

    module_function

    def clean(fields, raw, locale:)
      raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      raw = raw.stringify_keys
      default = Locales.default
      values = []
      errors = {}
      typed = {}

      fields.each do |field|
        sent = raw[field.key]
        sent = nil unless sent.is_a?(String)
        typed[field.key] = sent.to_s
        value, error = answer(field, sent)
        errors[field.key] = error if error
        values << { "key" => field.key, "type" => field.type, "label" => field.label_in(default) || field.key, "value" => value,
                    "display" => value.nil? ? "" : field.field_type.display.call(value, field, locale: default) }
      end

      Result.new(values: values, errors: errors, typed: typed)
    end

    # The cast value and the error, if any, of one field.
    def answer(field, sent)
      value_type = ContentModel::FieldTypes.fetch(field.field_type.value_type)
      value = sent.blank? ? nil : value_type.cast.call(sent)
      # A checkbox is true or false; unticked is an answer of "no", which a
      # required one refuses. The type is asked what an absent value is by
      # its value type, not by its name.
      return [ value, (:blank if field.required) ] if value.nil? && sent.blank?
      return [ nil, :invalid ] if value.nil?
      return [ value, :blank ] if field.required && value == false

      scratch = ActiveModel::Errors.new(Object.new)
      value_type.validate.call(field: field.definition_field, value: value, raw: sent, errors: scratch, stored: nil, translations: {})
      [ value, scratch.details[field.key.to_sym]&.first&.dig(:error) ]
    end
  end
end
