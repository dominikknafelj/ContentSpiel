module Blocks
  module FormFields
    # One value from the editor's choices, drawn as a `<select>` (the first
    # option the "Choose" word, which is no value) or as radios in a
    # `<fieldset>` named by its `<legend>` (`field.display`). `value` is the
    # chosen key. The fieldset carries the description (help and error); the
    # invalid mark is on each radio, as `aria-invalid` is not for a group.
    class ChoiceComponent < Base
      include Blocks::Contract

      contract(
        accessibility: "Radios in a fieldset named by its legend, or a select named by its label whose first option is \"Choose\"; \"required\" in words, the help and the error describe it, and aria-invalid marks an error.",
        motion: :none,
        content_edges: %i[short long missing many],
        widths: :container,
        interface: %i[field value error],
        words: %w[public.forms.required public.forms.choose public.forms.errors.*],
        limits: [
          "It draws one field from field, value and error; the ids, the name, the choices and the words are Forms::PublicField's."
        ]
      )
    end
  end
end
