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
    # block spec decision 7) is drawn as a SEGMENTED CONTROL instead: a
    # fieldset named by its legend, one radio per choice inside its own
    # label, the radio visually hidden and the label drawn as the segment.
    # Radios underneath, so the arrow keys move the choice and a change
    # bubbles to the form's autosave like a select's; a form someone else
    # holds disables every radio (`HeldFields`).
    class SelectField < Base
      # The posts list's scope toggle's look (`PostsScreen::ToolbarComponent::
      # SEGMENT_CLASS`: the chosen segment inverted, ink on paper, with a
      # paper focus ring), with a disabled state for a held or view-only
      # form. The group around the segments is outlined in
      # `border-field-line`, as every control is.
      SEGMENT_CLASS = "flex cursor-pointer items-center border-r border-line px-3 py-1.5 text-sm text-dim last:border-r-0 hover:bg-sunken " \
                      "has-[:checked]:bg-ink has-[:checked]:font-semibold has-[:checked]:text-paper has-[:checked]:hover:bg-ink " \
                      "has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:-outline-offset-2 has-[:focus-visible]:outline-accent " \
                      "has-[:checked]:has-[:focus-visible]:outline-paper has-[:checked]:has-[:focus-visible]:-outline-offset-4 " \
                      "has-[:disabled]:cursor-not-allowed has-[:disabled]:opacity-60 has-[:disabled]:not-has-[:checked]:hover:bg-transparent".freeze

      def option_pairs
        options = field.options[:options]
        return options.map { |v, l| [ l, v ] } if options.is_a?(Hash)

        Array(options).map { |v| [ v.to_s, v ] }
      end

      # The empty choice of a select that is not required: unnamed, unless
      # the field says what it means (`blank: "Plain text"`).
      def blank_choice = field.required? ? false : (field.options[:blank] || true)

      def segment_id(option) = "#{input_id}-#{option}"

      def checked?(option) = value.to_s == option.to_s
    end
  end
end
