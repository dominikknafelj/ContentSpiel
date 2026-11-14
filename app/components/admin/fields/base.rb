module Admin
  module Fields
    # Shared shape for every per-type field input `Admin::Ui::FieldComponent`
    # dispatches to (spec §4.3). All five of `Ui::FieldComponent`'s own
    # constructor keywords are forwarded here unchanged, even though a
    # scalar type (string, integer, url, ...) only ever reads
    # `field`/`form_name`/`value` -- `group` and `groups` are the two that
    # actually recurse back into `Ui::FieldComponent` per subfield and need
    # `original`, `locale` and `errors` too. Keeping one signature for every
    # subclass is what lets `Ui::FieldComponent#input_component` construct
    # whichever one it dispatches to without a type-by-type special case.
    # `placeholder:` is what the caller hands a field that shows one
    # (`Admin::Fields::StringField`); every other type ignores it.
    # `importable:` true is a caller that can take a file into the field
    # now: one that may change it (not held by someone else, not drawn for a
    # reader) and draws what an import needs outside the form
    # (`outside_form`). Only then does an input draw its import control
    # (`label_end`); it is false unless asked for, so no other caller draws
    # a control with nothing behind it.
    class Base < Admin::AdminComponent
      # How a value of this type reads where it cannot be edited (a
      # translation tab's "Shared fields", `EditorScreen::SharedFieldsComponent`):
      # a String, nil for nothing to show, or a `CodeDisplay` for code drawn
      # in a `pre`. A type's
      # input answers it, so the read-only view asks no type by its name.
      def self.display(_field, value) = value.to_s

      # Whether this input draws its own label beside it (a checkbox, a row
      # of buttons with its legend), so `Ui::FieldComponent` draws none.
      def self.own_label?(_field) = false

      # Whether a translation tab draws the original beside this input (the
      # reference card, with its Translate and Suggest update buttons). An
      # input nobody types in (a drawing the preview script writes) has
      # nothing a translator compares, so it answers false.
      def self.reference?(_field) = true

      # Whether the input is a hidden one nobody types in (a drawing the
      # preview script writes): `Ui::FieldComponent` then draws the input and
      # its error slot alone, in a wrapper that takes no room in the form (no
      # box, no gap in its column) until the slot holds an error.
      def self.hidden?(_field) = false

      # Data for the field's wrapper (`Ui::FieldComponent`'s `.admin-field`),
      # for an input whose script reaches beyond the input (the Mermaid
      # source's preview, drawn under a translation pair). Read after the
      # input is rendered.
      def field_data = {}

      # What the field draws under a translation pair, the pair's width, or
      # nil. Read after the input is rendered.
      def below_pair = nil

      # What the input needs drawn after its form, as a component, or nil: a
      # confirmation dialog, whose `<form method="dialog">` cannot stand
      # inside the form (the Mermaid source's "Replace the source?"). The
      # block card asks it only where its fields can be changed now.
      def self.outside_form(_field, _input_id) = nil

      # A control at the end of the label's row (the Mermaid source's Import
      # file…), or nil. Read after the input is rendered.
      def label_end = nil

      # `id_prefix:` mirrors `Ui::FieldComponent`'s own (see its comment) --
      # forwarded here unchanged so `input_id` agrees with the wrapping
      # `Ui::FieldComponent#errors_id` a Turbo Stream targets, whichever one a
      # caller supplied.
      def initialize(field:, form_name:, value:, original: nil, locale: nil, errors: [], id_prefix: nil, placeholder: nil, importable: false)
        @field = field
        @form_name = form_name
        @value = value
        @original = original
        @locale = locale
        @errors = errors
        @id_prefix = id_prefix || Admin::Ui::FieldComponent.dom_id_prefix(form_name)
        @placeholder = placeholder
        @importable = importable
      end

      private

      attr_reader :field, :form_name, :value, :original, :locale, :errors, :id_prefix, :placeholder

      def importable? = @importable

      def input_name = "#{form_name}[#{field.name}]"

      def input_id = "#{id_prefix}-#{field.name}"

      # The id of the help line `Admin::Ui::FieldComponent` draws under a
      # field whose type gives one (`help:`), for the input's `aria-describedby`.
      def help_id = field.help ? "#{input_id}-help" : nil

      # A container may be a `ContentModel::FieldSet` instance (a real
      # reader per field name), a plain Hash (an admin form's raw params, or
      # a Lookbook preview's in-memory sample), or absent entirely -- used
      # by `GroupField`/`GroupsField` to read a subfield out of whichever
      # shape `value`/`original` happens to be without needing a real
      # `FieldSet` in hand (test-only definitions in Lookbook previews never
      # register one).
      #
      # The Hash branch is checked *before* `respond_to?` -- a subfield can
      # legitimately be named `count`, `size`, `key`, `select`, `first`,
      # `type`, ... any of `Hash`'s own method names -- so checking
      # `respond_to?` first would silently call that method instead of
      # reading the key for exactly those names. `FieldSet` instances are
      # never `Hash`es, so this doesn't change how those are read.
      def read_field(container, name)
        return nil if container.nil?
        return container[name] || container[name.to_s] if container.is_a?(Hash)
        return container.public_send(name) if container.respond_to?(name)

        nil
      end
    end
  end
end
