module Blocks
  module FormFields
    # What every public form input shares (forms plan, Task 1): a real
    # `<label for>` with the label as TEXT (an editor typed it), "required"
    # in words inside the label (never a colour or an asterisk alone), the
    # help line under it, and an error that the control is tied to with
    # `aria-describedby` and `aria-invalid`. The ids come from
    # `Forms::PublicField`, which carries the Form block's id, so one form
    # placed twice on a page keeps its ids apart.
    #
    # Placeholder look: the default theme's existing field classes, none of
    # its own until the Form block's stylesheet (forms plan, Task 7).
    # `field` is a `Forms::PublicField`, `value` what the visitor typed (a
    # String, or true for a ticked box), `error` a key of `public.forms.errors`.
    class Base < ApplicationComponent
      ERRORS = %i[blank invalid inclusion too_long].freeze

      def initialize(field:, value: nil, error: nil)
        @field = field
        @value = value
        @error = error&.to_sym
      end

      private

      attr_reader :field, :value, :error

      # The control's aria: help and error, in that order, when there are any.
      def described_by = [ (field.help_id if field.help.present?), (field.error_id if error) ].compact.join(" ").presence

      def error_text = field.word("errors.#{ERRORS.include?(error) ? error : :invalid}")

      def required_word = field.word(:required)

      # The label's text and, when required, the word, inside it. All text:
      # `tag` escapes what an editor typed.
      def label_content
        safe_join([ field.label.to_s, (tag.span(required_word, class: "form-field__required") if field.required?) ].compact, " ")
      end

      def label_html = tag.label(label_content, for: field.id, class: "form-field__label")

      def help_html = (tag.p(field.help, id: field.help_id, class: "form-field__help") if field.help.present?)

      def error_html = (tag.p(error_text, id: field.error_id, class: "form-field__error") if error)

      # The attributes every text-like control carries.
      def control_attributes
        { name: field.name, id: field.id, required: field.required?, maxlength: field.max_length,
          aria: { describedby: described_by, invalid: (true if error) } }
      end
    end
  end
end
