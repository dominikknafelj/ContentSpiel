module Admin
  # A labelled password input with a Show/Hide button and, optionally, a
  # four-bar strength meter (design pass spec §4, handoff §9 A10). One
  # component for every password input in the product -- setup, new user,
  # change password, reset -- so the rule's wording, the toggle and the
  # meter never drift apart between screens. The behaviour is the Stimulus
  # `password-field` controller (app/javascript/controllers/, not `admin/`:
  # sign-in, reset and setup load the `application` entry only).
  #
  # `meter: false` is for a current password and every confirmation field:
  # a strength reading there would be noise. `errors` are bare messages
  # (e.g. "Use at least 12 characters."), printed under the field and tied
  # to the input through `aria-describedby`/`aria-invalid`.
  #
  # The Show/Hide button is 12px medium sans in the accent colour (handoff
  # "Studio Password Reset"), the same on every screen that renders this.
  # The optional `label_aside` slot puts a small link on the label row, to its
  # right -- sign-in's "Forgot your password?".
  #
  # The password itself is never rendered back: the input has no `value`.
  class PasswordFieldComponent < AdminComponent
    renders_one :label_aside

    def initialize(name:, id:, label:, meter: false, autocomplete: "new-password", errors: [], required: true, **input_html)
      @name = name
      @id = id
      @label = label
      @meter = meter
      @autocomplete = autocomplete
      @errors = Array(errors)
      @required = required
      @input_html = input_html
    end

    private

    attr_reader :name, :id, :label, :meter, :autocomplete, :errors, :required, :input_html

    def errors_id = "#{id}-errors"

    def hint_id = "#{id}-hint"

    def describedby
      [ (errors_id if errors.any?), (hint_id if meter) ].compact.join(" ").presence
    end

    def input_attrs
      {
        type: "password", name: name, id: id, autocomplete: autocomplete, required: required, maxlength: 72,
        class: "#{setup_input_class} pr-16",
        data: { password_field_target: "input", action: "input->password-field#measure" },
        aria: { invalid: (errors.any? ? "true" : nil), describedby: describedby }.compact
      }.merge(input_html)
    end
  end
end
