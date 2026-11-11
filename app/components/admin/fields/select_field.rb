module Admin
  module Fields
    # A `<select>` (spec §4.3), for `:select` fields. `field.options[:options]`
    # is either a `{value => label}` Hash (`ContentModel::Definition#field`'s
    # own doc) or a bare Array of values used as both -- `option_pairs`
    # normalizes either shape into `[label, value]` pairs for
    # `options_for_select`, which is what actually marks the current `value`
    # `selected`.
    #
    # A field that says `control: :segmented` (the Note block's kind, note
    # block spec decision 7) is drawn as the shared SEGMENTED CONTROL instead
    # (`Admin::Ui::SegmentedComponent`'s radios): a fieldset named by its
    # visible legend, one radio per choice inside its own label.
    # Radios underneath, so the arrow keys move the choice and a change
    # bubbles to the form's autosave like a select's; a form someone else
    # holds disables every radio (`HeldFields`).
    class SelectField < Base
      # The label an editor picked, not the stored value; the empty choice by
      # its own label where it has one; a value that is no longer on the list
      # as it is stored.
      def self.display(field, value)
        return field.options[:blank].to_s if value.blank?

        options = field.options[:options]
        (options[value.to_s] if options.is_a?(Hash)) || value.to_s
      end

      # A segmented control's legend is its label.
      def self.own_label?(field) = field.segmented?

      def option_pairs
        options = field.options[:options]
        return options.map { |v, l| [ l, v ] } if options.is_a?(Hash)

        Array(options).map { |v| [ v.to_s, v ] }
      end

      # The empty choice of a select that is not required: unnamed, unless
      # the field says what it means (`blank: "Plain text"`).
      def blank_choice = field.required? ? false : (field.options[:blank] || true)

      # The choices as the shared segmented control's radios.
      def segments = option_pairs.map { |label, option| { label:, value: option, id: "#{input_id}-#{option}", current: value.to_s == option.to_s } }
    end
  end
end
