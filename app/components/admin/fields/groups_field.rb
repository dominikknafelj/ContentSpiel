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
    # Per-subfield errors are threaded by the caller directly (cs-studio
    # Task 7, carried in from Task 2's review): `Admin::PostsController`
    # replaces each row's own error slot by the exact same id
    # `Admin::FieldComponent`'s default `dom_id_prefix(form_name)` already
    # derives for `row_form_name(index)` below -- see that controller's
    # `group_error_streams` -- so nothing here has to *receive* them, only
    # render the (initially always empty, see `Admin::FieldComponent`'s own
    # class comment for why) slot each subfield's own `FieldComponent`
    # already reserves.
    #
    # `original` rows are matched to this field's own rows by plain index
    # (`original_rows[index]`) -- an approximation, not a guarantee: an
    # editor who adds or removes rows independently per locale sees a
    # comparison against whatever the default language currently has at the
    # *same position*, not a guaranteed match to "the same speaker".
    # Correctly translating a `groups` field's own row *identity* across
    # locales (matching by some stable per-row key) is a later task; this is
    # still strictly more useful than showing no comparison at all, the same
    # trade-off `GroupField` already makes for its own single nested group.
    class GroupsField < Base
      def group_definition = FieldGroups.fetch(field.options[:of])

      def subfields = group_definition.fields

      def rows = Array(value).each_with_index.map { |row, index| [ index, row ] }

      def row_form_name(index) = "#{input_name}[#{index}]"

      # The root of this whole form's own param namespace ("post" or
      # "block", never anything nested) -- see the hidden marker rendered in
      # this component's own template for what this feeds (cs-studio
      # final-fixes round, finding 2). Derived from `form_name` rather than
      # threaded through as its own keyword: every caller today only ever
      # hands this component a bracketed name whose *first* segment already
      # is that root ("post[fields]", "block[settings]"), so there is
      # nothing a new keyword would let a caller say that this can't already
      # read off the one it's given.
      def root_form_name = form_name.to_s[/\A[^\[]+/]

      def subfield_value(row_value, subfield) = read_field(row_value, subfield.name)

      def original_rows = Array(original)

      def subfield_original(index, subfield) = read_field(original_rows[index], subfield.name)

      def singular = group_definition.label.to_s.singularize

      def add_label = "Add #{singular}"

      # The × says only "×" on screen, so a screen reader needs what it removes.
      def remove_label = "Remove #{singular}"
    end
  end
end
