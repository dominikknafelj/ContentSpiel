module Blocks
  module FormFields
    # A multi-line input; see `Base`.
    class LongTextComponent < Base
      include Blocks::Contract

      contract(
        accessibility: "A six-row textarea named by its label, with \"required\" in words; its help and its error describe it, and aria-invalid marks an error.",
        motion: :none,
        content_edges: %i[short long missing],
        widths: :from_container,
        interface: %i[field value error],
        words: %w[public.forms.required public.forms.errors.*],
        limits: [
          "It draws one field from field, value and error; the ids, the name and the words are Forms::PublicField's."
        ]
      )
    end
  end
end
