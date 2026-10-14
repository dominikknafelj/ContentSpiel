# Registry of block types (spec §3.1: `rich_text`, `image`, `post_list`, and
# whatever a plugin or, later, an admin-defined type adds). Filled from
# `config/initializers/types.rb`; nothing but that initializer and tests
# should call `register`/`reset!` directly.
module BlockTypes
  extend ContentModel::Registry

  def self.definition_class = ContentModel::BlockTypeDefinition
  def self.kind_label = "block type"

  # The built-in block types, in the order they were registered (the
  # picker's): each registered type that a module of its own under
  # `BlockTypes` registers (`code` by `BlockTypes::Code`, in
  # app/models/block_types/), which is what a call in
  # config/initializers/types.rb is and what the generator writes. Derived
  # from the registry and the modules rather than written as a list, so a new
  # built-in touches no list but the theme contract's ledger; not a record
  # taken while the initializer runs, because the tests reset the registry
  # and put its definitions back (`registry_put`), which a record would not
  # survive. An outside type (`gallery/album`) has an owner, and a bare name
  # a test registers (`quote`, `test_band`) has no module, so neither is one.
  def self.built_in_names
    names.select { |name| !name.include?("/") && const_defined?(name.camelize, false) }
  end

  # One component, one line of the theme contract (`Theme::Contract.components`
  # is keyed by the component's path, and a second line for one path would
  # replace the first in silence): a type that hands out a component another
  # registered type hands out already is refused, whichever registered
  # first. An outside type (`gallery/album`) would otherwise replace a
  # built-in's line, a promise to every theme, with its gem's, and two gems
  # one another's.
  def self.admit!(definition)
    return if definition.component.nil?

    other = all.find { |each| each.component == definition.component }
    return if other.nil?

    raise ArgumentError, "#{definition.name}: the block type hands out #{definition.component.name}, the component of the type " \
                         "#{other.name.inspect}: a block type hands out a component of its own (one component, one line of the theme contract)"
  end
  private_class_method :admit!

  # What the public stylesheet's build needs of the registered types, as
  # data for lib/theme_css.rb (block types spec, decision 7): each type's
  # stylesheet, and its component's folder where that is not
  # app/components/blocks, with or without a template file beside the
  # component (`component_folder`), and the type's name for a message.
  def self.theme_css_blocks(root: Rails.root)
    scanned = Pathname(root).join("app/components/blocks")
    all.map do |definition|
      folder = definition.component_folder
      ThemeCss::Block.new(stylesheet: definition.stylesheet_path(root: root), source: (folder unless folder.nil? || folder == scanned),
                          type: definition.name)
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
