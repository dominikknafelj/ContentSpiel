# Route constraint for a `:locale` segment (spec §4.4): the enabled languages
# are a runtime setting, so a fixed regex in routes.rb can't express them. A
# failed constraint makes the router try the next route, which is what lets
# "/preview/about" fall through to the unprefixed preview route.
module LocaleRouteConstraint
  module_function

  def matches?(request)
    Locales.enabled?(request.path_parameters[:locale])
  end
end
