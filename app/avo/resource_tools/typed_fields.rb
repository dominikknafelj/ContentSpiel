# The typed, schema-driven editor for a record's own type-specific values
# (open-types spec §6): a Post's `fields` or a ContentBlock's `settings`,
# rendered from the record's own type definition rather than a raw
# key/value editor. A resource tool, not a plain field, for the same reason
# NestedContentBlocks is one: the actual inputs (`app/views/avo/partials/
# _typed_fields.html.erb`) are schema-driven markup a `field` declaration
# can't produce on its own, and -- for Post specifically -- there is no
# clean Avo field/`update_using` path at all, since that only ever fires for
# a record that already has a real `<name>=` method per field name (see the
# comment on `Avo::Resources::Post#fields`).
#
# Reused by both `Avo::Resources::Post` and `Avo::Resources::ContentBlock`,
# distinguishing which by `param_key`/`current_values` below, rather than one
# copy per resource: the two records differ only in which top-level param
# key their typed inputs write into and which method reads their current
# values back, everything else about rendering a type's fields is identical.
class Avo::ResourceTools::TypedFields < Avo::BaseResourceTool
  self.name = "Fields"

  # The nested-params key this record's typed inputs write into: an existing
  # jsonb column for a ContentBlock (`settings`, the same raw-then-
  # `normalize_settings` path the page form's nested block rows already
  # write through), or `Post#fields=` for a Post (there's no raw `fields`
  # column to fall back to, so this goes straight through `assign_fields`).
  def param_key(record) = record.is_a?(::ContentBlock) ? :settings : :fields

  # The type's `ContentModel::FieldSet` instance to read each field's
  # current value from, or nil when the record's own type isn't registered
  # (nothing to render).
  def current_values(record) = record.is_a?(::ContentBlock) ? record.settings_object : record.fields
end
