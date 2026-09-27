module Admin
  module Fields
    # An add/remove/reorder list of `group` rows (spec §4.3), for `groups`
    # fields (e.g. `test/event#speakers`). Rows are named
    # `form_name[field][index][subfield]`; a hidden `<template>` holds one
    # blank row with the literal placeholder `__INDEX__` in place of an
    # index, which `app/javascript/controllers/admin/groups_controller.js`
    # clones and renumbers on "Add" -- see that file for the add/remove/
    # reorder mechanics this only has to render the markup for.
    #
    # As with `GroupField`, per-row/per-subfield errors don't thread through
    # here yet (see that class's comment) -- and neither does `original`:
    # unlike a single `group`, there's no obvious index-for-index
    # correspondence between a `groups` value and its default-locale
    # original once rows have been added or removed independently per
    # locale, so translating a `groups` field's rows is left to a later
    # task rather than this component guessing at a mapping.
    class GroupsField < Base
      def group_definition = FieldGroups.fetch(field.options[:of])

      def subfields = group_definition.fields

      def rows = Array(value).each_with_index.map { |row, index| [ index, row ] }

      def row_form_name(index) = "#{input_name}[#{index}]"

      def subfield_value(row_value, subfield) = read_field(row_value, subfield.name)

      def add_label = "Add #{group_definition.label.to_s.singularize}"
    end
  end
end
