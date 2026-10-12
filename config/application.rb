require_relative "boot"
require_relative "supported_locales"

# `rails/all` minus ActionText (tiptap design spec §5): rich text is stored
# as per-locale JSON documents (`HasRichTextBody`, `RichText::Document`),
# and ActionText's engine would otherwise still boot its models, routes,
# helpers and the Trix/actiontext importmap assets. Active Storage stays --
# `Media::Asset` and image blocks use it directly, and it never depended on
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

# Required here although lib/ is autoloaded (`config.autoload_lib` below):
# config/environments/production.rb calls HostSettings while the application
# is being configured, before any autoloading is set up.
require_relative "../lib/site_address"
require_relative "../lib/host_settings"

# And these two for another reason: config/initializers/opentelemetry.rb
# hands their objects to the OpenTelemetry SDK for the life of the process
# (lib/telemetry.rb says the rest).
require_relative "../lib/telemetry"
require_relative "../lib/telemetry/path_scrubber"

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

    # Lets config/locales/en.yml set a per-attribute `format` for validation
    # messages (Rails ignores it otherwise). Used for exactly one thing:
    # User's password length message is a whole sentence ("Use at least 12
    # characters.") that must read the same everywhere, without a "Password "
    # prefix in `full_messages`.
    config.active_model.i18n_customize_full_message = true

    # Active Record encryption -- today only for the AI API key
    # (`SiteSetting` `encrypts :ai_api_key`, translation helpers spec §6.2).
    # Keys come from, in order of precedence:
    # - `ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]`, `..._DETERMINISTIC_KEY`
    #   and `..._KEY_DERIVATION_SALT`, set below only when present -- a nil
    #   here would override the credentials, since Rails merges this config
    #   over them;
    # - otherwise `active_record_encryption.primary_key`/`deterministic_key`/
    #   `key_derivation_salt` in the app's credentials, which Rails reads by
    #   itself (`bin/rails db:encryption:init` prints a fresh set).
    # The precedence is per key, not per set: with only some of the three
    # env vars present, the rest still come from the credentials, and the
    # app runs on a mix of two sets. Keep all three in the same place.
    # Test and development set fixed values of their own
    # (config/environments/test.rb, development.rb), so CI needs nothing.
    #
    # Production must provide one or the other. Nothing is checked at boot:
    # with no keys, the app runs normally until something actually encrypts
    # or decrypts -- saving an AI key in Settings raises
    # `ActiveRecord::Encryption::Errors::Configuration` right there, and a
    # site that never saves one never needs keys. Keep them once set:
    # losing them makes a stored key unreadable (remove and re-enter it).
    %w[primary_key deterministic_key key_derivation_salt].each do |name|
      value = ENV["ACTIVE_RECORD_ENCRYPTION_#{name.upcase}"]
      config.active_record.encryption[name.to_sym] = value if value.present?
    end
    # Rails' own default, spelled out: a value that isn't an encryption
    # payload (written around the model) is an error, never read as
    # plaintext.
    config.active_record.encryption.support_unencrypted_data = false

    # Production says at boot which address it serves, and stops without
    # SECRET_KEY_BASE with a message of its own (lib/host_settings.rb).
    #
    # Where it runs matters. Rails raises its own error, the one that points
    # at `bin/rails credentials:edit`, the first time `secret_key_base` is
    # read; in this app that is Active Record's `generated_token_verifier` in
    # an `after_initialize` block, but any initializer, gem or eagerly loaded
    # class that asks for a key generator or a message verifier earlier would
    # move it. So the check is placed among Rails' bootstrap initializers:
    # after the logger exists (the environment file, which sets the logger
    # and parses PUBLIC_HOST, is loaded before that) and before every
    # railtie's and every `config/initializers` file's turn. `after:` alone
    # would not do it: an application's own initializers run after all the
    # engines' unless a `before:` pulls them forward.
    #
    # `SECRET_KEY_BASE_DUMMY` is the Dockerfile's asset precompilation, which
    # has no secret and needs none; Rails asks only whether it is set, and so
    # does this.
    initializer "content_spiel.host_announcement", after: :initialize_logger, before: :initialize_cache do
      if Rails.env.production?
        # The credentials are handed over unread: they are decrypted only if
        # the variable is not set, and what reading them can raise is
        # `require_secret!`'s to turn into its own message.
        HostSettings.require_secret!(ENV, credentials: Rails.application.credentials) unless ENV["SECRET_KEY_BASE_DUMMY"]
        HostSettings.announcement(SiteAddress.current, ENV).each { |line| Rails.logger.info line }
      end
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
