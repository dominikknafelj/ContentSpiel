require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ContentSpiel
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # The locales the site is published in. Mobility reads these back out of
    # this config (not out of I18n directly), and uses them to decide which
    # per-locale accessors and rich-text associations to define -- so this has
    # to be set here, before any model is loaded, rather than in an initializer.
    config.i18n.available_locales = %i[en de es]
    config.i18n.default_locale = :en

    # Fall back to English when a translation is missing. Set here rather than
    # only in production so that Mobility's fallbacks behave identically in
    # every environment (a translated attribute with no German value reads as
    # the English one).
    config.i18n.fallbacks = [ :en ]

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
