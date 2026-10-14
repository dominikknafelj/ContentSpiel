# Registry of block types (spec §3.1: `rich_text`, `image`, `post_list`, and
# whatever a plugin or, later, an admin-defined type adds). Filled from
# `config/initializers/types.rb`; nothing but that initializer and tests
# should call `register`/`reset!` directly.
module BlockTypes
  extend ContentModel::Registry

  def self.definition_class = ContentModel::BlockTypeDefinition
  def self.kind_label = "block type"

  # What the public stylesheet's build needs of the registered types, as
  # data for lib/theme_css.rb (block types spec, decision 7): each type's
  # stylesheet, and its component's folder where that is not
  # app/components/blocks.
  def self.theme_css_blocks(root: Rails.root)
    scanned = Pathname(root).join("app/components/blocks")
    all.map do |definition|
      folder = definition.component_template&.dirname
      ThemeCss::Block.new(stylesheet: definition.stylesheet_path(root: root), source: (folder unless folder.nil? || folder == scanned))
    end
  end

  # Blocks whose type can list posts (spec §6: `PublicSite::Paths`, the
  # permalink-resolution fallback and `ContentBlock#lists?` all key off this
  # instead of a hardcoded `block_type == "post_list"` check, so a plugin's
  # block type can opt in the same way.
  def self.with_capability(capability)
    all.select { |definition| definition.capability?(capability) }
  end
end
