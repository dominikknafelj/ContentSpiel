module Blocks
  module FormFields
    # One box, also a consent box: the label follows the box and is the
    # box's name. Unticked sends nothing, which `Forms::Answers` reads as no
    # (and a required one refuses). `value` is true (or "1") when ticked.
    class CheckboxComponent < Base
      include Blocks::Contract

      contract(
        accessibility: "One checkbox named by the label beside it, with \"required\" in words; its help and its error describe it, and aria-invalid marks an error.",
        motion: :none,
        content_edges: %i[short long missing],
        widths: :container,
        interface: %i[field value error],
        words: %w[public.forms.required public.forms.errors.*],
        limits: [
          "It draws one field from field, value and error; the ids, the name and the words are Forms::PublicField's."
        ]
      )
    end
  end
end
