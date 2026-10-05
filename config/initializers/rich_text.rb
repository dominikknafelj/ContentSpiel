# How the rich-text built-ins turn a view component into HTML
# (`RichText.component_renderer`, see its comment). A model can't name a
# controller, so the application hands it this: a component has no view
# context of its own, and `ApplicationController.render` builds one (the same
# mechanism a dispatched request uses), without a layout.
#
# In `to_prepare`, like every registry (`config/initializers/types.rb`): a
# code reload in development re-assigns it against the freshly loaded
# `ApplicationController` rather than leaving a lambda that closes over the old.
Rails.application.config.to_prepare do
  RichText.component_renderer = ->(component) { ApplicationController.render(component, layout: false) }
end
