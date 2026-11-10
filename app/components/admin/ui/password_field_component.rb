module Admin
  module Ui
    # A labelled password input with a Show/Hide button and, optionally, a
    # four-bar strength meter. One
    # component for every password input in the product -- setup, new user,
    # change password, reset -- so the rule's wording, the toggle and the
    # meter never drift apart between screens. The behaviour is the Stimulus
    # `password-field` controller (app/javascript/controllers/, not `admin/`:
    # sign-in, reset and setup load the `application` entry only).
    #
    # `meter: false` is for a current password and every confirmation field:
    # a strength reading there would be noise. `errors` are bare messages
    # (e.g. "Use at least 12 characters."), printed under the field as the
    # shared error slot draws them ("!" and the message) and tied to the
    # input through `aria-describedby`/`aria-invalid`.
    #
    # THE REFUSED LOOK IS THE COMPONENT'S OWN. The field stands outside an
    # `.admin-field` on most screens, and inside one its error slot is not
    # the wrapper's direct child, so the wrapper's rule cannot see it: while
    # `errors.any?` the root carries `.admin-password-field--invalid`, which
    # sets `--cs-field-invalid-border` to the danger colour for the well's
    # bottom edge (content-spiel.tailwind.css), kept under the focus ring.
    # A class set at render time is right here, where it is wrong for an
    # autosaving field: this form is sent whole and drawn again.
    #
    # Its words are keys (`admin.components.ui.password_field`): the server
    # draws Show and the rule line, and the script reads Hide, Show and the
    # meter's sentences from the root's `data-messages`.
    #
    # The Show/Hide button is 12px medium sans in the accent colour, the same
    # on every screen that renders this.
    # The optional `label_aside` slot puts a small link on the label row, to its
    # right -- sign-in's "Forgot your password?" -- which wraps under the
    # label where the row is too narrow for both.
    #
    # The password itself is never rendered back: the input has no `value`.
    class PasswordFieldComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A labelled password input with a Show button that controls it; errors and the meter's hint are tied to it by aria-describedby, and the hint is a polite live region.",
        motion: :none,
        content_edges: %i[none long],
        widths: :from_container,
        interface: %i[name id label meter autocomplete errors required],
        limits: [
          "The password is never drawn back: the input has no value."
        ],
        states: %i[rest meter invalid hover focus],
        script_states: {
          revealed: [ "test/system/password_field_test.rb", "the change-password form shows the meter, toggles visibility and blocks a short password" ],
          measured: [ "test/system/password_field_test.rb", "the change-password form shows the meter, toggles visibility and blocks a short password" ]
        },
        keys: %w[show hide minimum strength.too_short strength.fair strength.good strength.strong],
        slots: %i[label_aside],
        controller: "password-field"
      )

      renders_one :label_aside

      # What the script writes: the toggle's two words and the meter's four
      # sentences. The rule line before anything is typed is the server's.
      MESSAGES = %w[show hide strength.too_short strength.fair strength.good strength.strong]
        .map { |key| "components.ui.password_field.#{key}" }.freeze

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

      def script_messages = messages_data(*MESSAGES)

      def invalid? = errors.any?

      def root_class = [ "admin-password-field", ("admin-password-field--invalid" if invalid?) ].compact.join(" ")

      def errors_id = "#{id}-errors"

      def hint_id = "#{id}-hint"

      def describedby
        [ (errors_id if invalid?), (hint_id if meter) ].compact.join(" ").presence
      end

      def input_attrs
        {
          type: "password", name: name, id: id, autocomplete: autocomplete, required: required, maxlength: 72,
          class: "#{setup_input_class} pr-16",
          data: { password_field_target: "input", action: "input->password-field#measure" },
          aria: { invalid: (invalid? ? "true" : nil), describedby: describedby }.compact
        }.merge(input_html)
      end
    end
  end
end
