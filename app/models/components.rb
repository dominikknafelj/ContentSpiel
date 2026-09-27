# Registry of reusable field groups (spec §3.1/§3.3, e.g. `cta`, `speaker`)
# that a block or content type's own fields reference via `component`/
# `components` `of:`. Filled from `config/initializers/types.rb`; nothing but
# that initializer and tests should call `register`/`reset!` directly.
module Components
  extend TypeRegistry

  def self.definition_class = ComponentDefinition
  def self.kind_label = "component"
end
