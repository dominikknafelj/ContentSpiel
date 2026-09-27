# A registered, reusable field group (spec §3.1/§3.3, e.g. `cta`, `speaker`):
# a `TypeDefinition` whose own fields may not nest another `component`/
# `components` field (one level of nesting only -- no dynamic zones), plus
# the ViewComponent that renders one value of the group
# (`Fields::ComponentValueComponent`, sub-project 5).
class ComponentDefinition < TypeDefinition
  def component(klass = nil)
    klass.nil? ? @component : (@component = klass)
  end

  # Checked once the registration block has finished adding fields (called
  # by `TypeRegistry#register` before the definition is stored) rather than
  # inside `field` itself, so the order fields are declared in never matters.
  def finalize!
    return unless fields.any?(&:group?)

    raise ArgumentError, "components can't contain other components (one level only)"
  end
end
