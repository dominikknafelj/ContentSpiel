module Fields
  # Renders any field group generically, as a definition list of label =>
  # value (`FieldGroupDefinition#component`). No built-in block or content
  # type declares a `group`/`groups` field yet, so nothing renders through
  # this today -- it exists so a type that does (the roadmap's Task 5 test
  # type, and its own Lookbook preview) has a reasonable default without
  # writing its own component, the same way `Avo`'s generic settings
  # renderer (spec §6) gives every type a form for free.
  class GroupComponent < ApplicationComponent
    def initialize(value:)
      @value = value
    end

    # One label/value pair per scalar field in the group's own definition,
    # in declaration order. Nested `group`/`groups` fields are skipped --
    # `ContentModel::Definition` already forbids a field group from
    # containing another one (one level of nesting only, global
    # constraints), so this is a defensive skip rather than a real case:
    # rendering a group-of-groups recursively is future work a type that
    # actually has one can opt into with its own component.
    def rows
      value.definition.fields.reject(&:group?).map { |field| [ field.name.humanize, value.public_send(field.name) ] }
    end

    private

    attr_reader :value
  end
end
