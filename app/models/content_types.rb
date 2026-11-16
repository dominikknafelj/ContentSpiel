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

  # HOLDS THE SWITCHES for the rest of the caller's transaction: the settings
  # row is read `FOR SHARE`, which waits for a `Settings::Save` in flight (it
  # holds the row `FOR UPDATE` from its first statement to its commit) and
  # keeps the next one from committing a switch until this transaction ends.
  # So what a write decides from the switch (a post's refusal, its address in
  # `PublicSite::Paths`, its documents in `SiteSearch::Documents`) is the
  # switch as it stands at the write's commit, and a switch-off's refresh
  # never runs beside a write that still sees the type on.
  #
  # THE ORDER: the settings row before any `public_paths` row or search entry.
  # A switch writes those after its own lock and writes no page or post row,
  # so a writer that already holds its record's row (`take!`, a save's
  # UPDATE) waits here without a cycle.
  #
  # `Current.site` becomes the row read when it was written since the memo
  # was loaded (a switch committed since the request began); a memo with
  # changes not yet saved is this transaction's own write of the row and is
  # kept as it is. Outside a transaction the lock ends with its statement.
  # Answers nil.
  def self.hold!
    site = Current.site
    return nil if site.new_record? || site.has_changes_to_save?

    held = SiteSetting.lock("FOR SHARE").find(site.id)
    Current.site = held unless held.updated_at == site.updated_at
    nil
  end

  # One component, one line of the theme contract (`Theme::Contract
  # .post_components` is keyed by the component's path): a type that declares
  # a component another registered type declares already must declare the same
  # methods (the three built-ins share `Posts::DetailComponent`), or the one
  # registered second would replace the first's line in silence.
  def self.admit!(definition)
    definition.component_lines.each do |component, methods|
      other = all.find { |registered| registered.component_lines[component] && registered.component_lines[component] != methods }
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
