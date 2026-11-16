# Registry of content types (spec §3.1: `blog`, `resume_entry`, `now_update`).
# Filled from `config/initializers/types.rb`; nothing but that initializer
# and tests should call `register`/`reset!` directly. A gem cannot add one:
# there is no hook replaying an outside content type after the `reset!`.
module ContentTypes
  extend ContentModel::Registry

  def self.definition_class = ContentModel::ContentTypeDefinition
  def self.kind_label = "content type"

  # Two sets: the DECLARED types (`all`, `names`) are the code's; the
  # SWITCHED-ON types are the declared ones the site names in
  # `site_settings.content_types`, in registration order. A name the site
  # holds that is not declared is carried but never switched on. Which set a
  # reader takes is the list in `test/lib/content_type_sets_test.rb`: the
  # public site, search and the editors' choices read the switched-on set.
  def self.switched_on(site: Current.site)
    chosen = site.content_types
    all.select { |definition| chosen.include?(definition.name.to_s) }
  end

  def self.switched_on_names(site: Current.site) = switched_on(site: site).map(&:name)

  def self.switched_on?(name, site: Current.site) = switched_on_names(site: site).map(&:to_s).include?(name.to_s)

  # One component, one line of the theme contract (`Theme::Contract
  # .post_components` is keyed by the component's path): a type that declares
  # a component another registered type declares already must declare the same
  # methods (the three built-ins share `Posts::DetailComponent`), or the one
  # registered second would replace the first's line in silence.
  def self.admit!(definition)
    definition.component_lines.each do |component, methods|
      other = all.find { |each| each.component_lines[component] && each.component_lines[component] != methods }
      next if other.nil?

      raise ArgumentError, "#{definition.name}: declares #{component.name} with the methods #{methods.inspect}, the type #{other.name.inspect} " \
                           "declares it with #{other.component_lines[component].inspect}: one component, one line of the theme contract"
    end
  end
  private_class_method :admit!

  # The type new posts default to: the first switched on (registration order,
  # `blog` first), else the first declared, so a bare "new post" form always
  # has *a* type to start from.
  def self.default = switched_on.first || all.first
end
