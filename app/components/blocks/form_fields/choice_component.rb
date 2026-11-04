module Blocks
  module FormFields
    # One value from the editor's choices, drawn as a `<select>` (the first
    # option the "Choose" word, which is no value) or as radios in a
    # `<fieldset>` named by its `<legend>`. `value` is the chosen key.
    class ChoiceComponent < Base
      private

      def radios? = field.display == "radios"

      def chosen?(choice) = value.to_s == choice.key

      def radio_id(choice) = field.choice_id(choice)

      # The fieldset carries the description (help and error); the invalid
      # mark is on each radio, as `aria-invalid` is not for a group.
      def group_attributes = { aria: { describedby: described_by } }

      def select_attributes = control_attributes.except(:maxlength)

      def radio_attributes(choice)
        { type: "radio", name: field.name, id: radio_id(choice), value: choice.key, checked: chosen?(choice), required: field.required?, aria: { invalid: (true if error) } }
      end
    end
  end
end
