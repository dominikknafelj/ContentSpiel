module Blocks
  module FormFields
    # A single-line input (`type="email"`); see `Base`.
    class EmailComponent < Base
      include Blocks::Contract

      contract(
        accessibility: "An email input named by its label, with \"required\" in words and autocomplete=email; its help and its error describe it, and aria-invalid marks an error.",
        motion: :none,
        content_edges: %i[short long missing],
        widths: :from_container,
        interface: %i[field value error],
        words: %w[public.forms.required public.forms.errors.*],
        limits: [
          "It draws one field from field, value and error; the ids, the name and the words are Forms::PublicField's.",
          "The browser checks the address before a send; the endpoint checks it again."
        ]
      )
    end
  end
end
