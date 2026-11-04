module Blocks
  module FormFields
    # What every public form input shares (forms plan, Tasks 1 and 7): a real
    # `<label for>` with the label as TEXT (an editor typed it), "required"
    # in words inside the label (never a colour or an asterisk alone), the
    # help line under it, and an error that the control is tied to with
    # `aria-describedby` and `aria-invalid`. The ids come from
    # `Forms::PublicField`, which carries the Form block's id, so one form
    # placed twice on a page keeps its ids apart.
    #
    # THE ERROR ELEMENT IS ALWAYS DRAWN (pre-flight R15; design.md 4.3):
    # empty and `hidden` without an error, and named by `aria-describedby`
    # only while it holds one (`PublicField#described_by`), so the Form
    # block's script writes a message into the element the template drew and
    # never builds one: a theme decides where an error stands.
    #
    # A THEME MAY REPLACE EACH TEMPLATE (`Theme::Contract.components`, the
    # five inputs' lines): a template calls `field`, `value` and `error` and
    # nothing else of its component, so the templates write their markup out
    # from those three, and what they ask of `field` is the public field's
    # readers (docs/reference/theming.md, "The Form block"). `field` is a
    # `Forms::PublicField`, `value` what the visitor typed (a String, or true
    # or "1" for a ticked box), `error` a key of `public.forms.errors` or nil.
    #
    # The look is the default theme's `form.css`, and on the endpoint's plain
    # page the CMS's own (`.form-send-page`, content-spiel.tailwind.css).
    class Base < ApplicationComponent
      def initialize(field:, value: nil, error: nil)
        @field = field
        @value = value
        @error = error&.to_sym
      end

      private

      attr_reader :field, :value, :error
    end
  end
end
