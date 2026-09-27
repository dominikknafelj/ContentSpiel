module Admin
  module Fields
    # Shared shape for every per-type field input `Admin::FieldComponent`
    # dispatches to (spec §4.3). All five of `FieldComponent`'s own
    # constructor keywords are forwarded here unchanged, even though a
    # scalar type (string, integer, url, ...) only ever reads
    # `field`/`form_name`/`value` -- `group` and `groups` are the two that
    # actually recurse back into `FieldComponent` per subfield and need
    # `original`, `locale` and `errors` too. Keeping one signature for every
    # subclass is what lets `FieldComponent#input_component` construct
    # whichever one it dispatches to without a type-by-type special case.
    class Base < Admin::AdminComponent
      def initialize(field:, form_name:, value:, original: nil, locale: nil, errors: [])
        @field = field
        @form_name = form_name
        @value = value
        @original = original
        @locale = locale
        @errors = errors
      end

      private

      attr_reader :field, :form_name, :value, :original, :locale, :errors

      def input_name = "#{form_name}[#{field.name}]"

      def input_id = Admin::FieldComponent.dom_id_prefix(form_name) + "-" + field.name

      # A container may be a `ContentModel::FieldSet` instance (a real
      # reader per field name), a plain Hash (an admin form's raw params, or
      # a Lookbook preview's in-memory sample), or absent entirely -- used
      # by `GroupField`/`GroupsField` to read a subfield out of whichever
      # shape `value`/`original` happens to be without needing a real
      # `FieldSet` in hand (test-only definitions in Lookbook previews never
      # register one).
      def read_field(container, name)
        return nil if container.nil?
        return container.public_send(name) if container.respond_to?(name)

        container.is_a?(Hash) ? container[name] || container[name.to_s] : nil
      end
    end
  end
end
