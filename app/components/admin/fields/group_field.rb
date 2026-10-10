module Admin
  module Fields
    # A nested fieldset of `Admin::Ui::FieldComponent`s for one `group` field's
    # own definition (spec §4.3) -- `field.options[:of]` names a
    # `FieldGroups` entry (e.g. `test/speaker`), and every one of *its*
    # fields renders exactly the way a top-level field would, just named
    # `form_name[field][subfield]` instead of `form_name[subfield]`.
    #
    # `value`/`original` are read once per subfield via `Base#read_field`,
    # which accepts a `FieldSet` instance, a plain Hash, or nil -- a group
    # field can arrive as any of the three depending on whether the caller
    # already has a real record's `FieldSet` in hand or is still building
    # one up from request params.
    #
    # Per-subfield errors aren't threaded through here: `errors:` on this
    # field renders nowhere (the wrapping `Ui::FieldComponent` already reserved
    # one shared errors slot for the whole group), and each subfield's own
    # `Ui::FieldComponent` gets an empty list. Splitting `ContentModel::FieldSet
    # #validate_group`'s dotted keys (`"speakers.0.name"`) back into
    # per-subfield arrays is the save controller's job in a later task, once
    # there's an actual `ApplicationService::Result` to read them from --
    # nothing here has one yet.
    class GroupField < Base
      def group_definition = FieldGroups.fetch(field.options[:of])

      def subfields = group_definition.fields

      def subfield_value(subfield) = read_field(value, subfield.name)

      def subfield_original(subfield) = read_field(original, subfield.name)
    end
  end
end
