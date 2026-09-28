require_relative "boot"
require_relative "supported_locales"

# `rails/all` minus ActionText (tiptap design spec §5): rich text is stored
# as per-locale JSON documents (`HasRichTextBody`, `RichText::Document`),
# and ActionText's engine would otherwise still boot its models, routes,
# helpers and the Trix/actiontext importmap assets. Active Storage stays --
# `MediaAsset` and image blocks use it directly, and it never depended on
# ActionText.
require "rails"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "active_job/railtie"
require "action_cable/engine"
require "action_mailbox/engine"
require "rails/test_unit/railtie"

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

    # The locales Mobility and I18n will accept reads and writes for. Mobility
    # reads these back out of this config (not out of I18n directly), and
    # uses them to decide which per-locale accessors and rich-text
    # associations to define -- so this has to be set here, before any model
    # is loaded, rather than in an initializer.
    #
    # Widened to every *supported* locale (spec §4.1) rather than pinned to
    # the three shipping ones: every loop that used to iterate "available"
    # locales (Mobility accessors, the sitemap, the locale route constraint)
    # was switched to `Locales.enabled` in earlier tasks, which is a runtime
    # setting (`site_settings.locales`) bounded by, but not equal to, this
    # list. This is only the outer bound on what a site is *capable* of
    # enabling -- Locales::Enable/Disable is what actually turns one on.
    config.i18n.available_locales = SUPPORTED_LOCALES.keys.map(&:to_sym)
    config.i18n.default_locale = :en

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
