module Blocks
  module FormFields
    # One value from the editor's choices, drawn as a `<select>` (the first
    # option the "Choose" word, which is no value) or as radios in a
    # `<fieldset>` named by its `<legend>` (`field.display`). `value` is the
    # chosen key. The fieldset carries the description (help and error); the
    # invalid mark is on each radio, as `aria-invalid` is not for a group.
    class ChoiceComponent < Base
    end
  end
end
