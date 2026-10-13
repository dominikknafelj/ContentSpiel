module Admin
  module Fields
    # A `<select>` (spec §4.3), for `:select` fields. `field.options[:options]`
    # is either a `{value => label}` Hash (`ContentModel::Definition#field`'s
    # own doc) or a bare Array of values used as both -- `option_pairs`
    # normalizes either shape into `[label, value]` pairs for
    # `options_for_select`, which is what actually marks the current `value`
    # `selected`.
    class SelectField < Base
      def option_pairs
        options = field.options[:options]
        return options.map { |v, l| [ l, v ] } if options.is_a?(Hash)

        Array(options).map { |v| [ v.to_s, v ] }
      end

      # The empty choice of a select that is not required: unnamed, unless
      # the field says what it means (`blank: "Plain text"`).
      def blank_choice = field.required? ? false : (field.options[:blank] || true)
    end
  end
end
