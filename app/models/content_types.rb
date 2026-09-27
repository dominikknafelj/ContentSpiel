# Registry of content types (spec §3.1: `blog`, `resume_entry`, `now_update`,
# and whatever a plugin or, later, an admin-defined type adds). Filled from
# `config/initializers/types.rb`; nothing but that initializer and tests
# should call `register`/`reset!` directly.
module ContentTypes
  extend TypeRegistry

  def self.definition_class = ContentTypeDefinition
  def self.kind_label = "content type"

  # The type new posts default to (registration order, spec §3.1's example
  # order is `blog` first) -- used wherever something needs *a* content type
  # without the caller having one in hand yet (e.g. a bare "new post" form).
  def self.default = all.first
end
