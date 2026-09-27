# A registered, reusable field group (spec §3.1/§3.3, e.g. `cta`, `speaker`):
# a `ContentModel::Definition` whose own fields may not nest another
# `group`/`groups` field (one level of nesting only -- no dynamic zones),
# plus the ViewComponent that renders one value of the group
# (`Fields::GroupComponent`, sub-project 5).
module ContentModel
  class FieldGroupDefinition < Definition
    dsl_attribute :component

    # Checked once the registration block has finished adding fields (called
    # by `ContentModel::Registry#register` before the definition is stored)
    # rather than inside `field` itself, so the order fields are declared in
    # never matters.
    def finalize!
      return unless fields.any?(&:group?)

      raise ArgumentError, "field groups can't contain other field groups (one level only)"
    end
  end
end
