# Registry of reusable field groups (spec §3.1/§3.3, e.g. `cta`, `speaker` --
# what Storyblok/Strapi call "components"; named `FieldGroups` here so they
# never get confused with `app/components/` ViewComponents) that a block or
# content type's own fields reference via `group`/`groups` `of:`. Filled
# from `config/initializers/types.rb`; nothing but that initializer and
# tests should call `register`/`reset!` directly.
module FieldGroups
  extend ContentModel::Registry

  def self.definition_class = ContentModel::FieldGroupDefinition
  def self.kind_label = "field group"
end
