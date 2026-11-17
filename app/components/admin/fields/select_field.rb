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

      # A segmented control and the select after it share a row on the block
      # card (the Gallery's Layout and Shape, StudioGallery D2).
      def self.opens_row?(field) = field.segmented?

      def self.fills_row?(_field) = true

      def option_pairs
        options = field.options[:options]
        return options.map { |v, l| [ l, v ] } if options.is_a?(Hash)

        Array(options).map { |v| [ v.to_s, v ] }
      end

      # The empty choice of a select that is not required and has no
      # default: unnamed, unless the field says what it means (`blank: "Plain
      # text"`). A field with a default has no empty choice: a block that
      # stores none is drawn with the default (the Gallery's Shape), so an
      # empty row would offer a choice that means the first one.
      def blank_choice
        return false if field.required? || field.options.key?(:default)

        field.options[:blank] || true
      end

      # The option marked selected: the stored value, or the default when the
      # block stores none.
      def chosen = value.presence || field.options[:default]

      # The choices as the shared segmented control's radios.
      def segments = option_pairs.map { |label, option| { label:, value: option, id: "#{input_id}-#{option}", current: value.to_s == option.to_s } }
    end
  end
end
