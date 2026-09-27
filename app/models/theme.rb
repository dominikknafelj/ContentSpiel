# The active public theme's component overrides (open-types spec §5). Only
# the lookup exists for now: the default theme uses each definition's own
# component. An alternate theme will map definition names to its own
# component classes here, with the definition's as the fallback.
class Theme
  def self.current = @current ||= new

  def component_for(definition, role = :component)
    definition.public_send(role)
  end
end
