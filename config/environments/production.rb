require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Everything a host decides about the site's address: which host names
  # are answered, whether HTTPS is forced, and the address in mailed links.
  # One variable, PUBLIC_HOST (see lib/host_settings.rb and the guide's
  # "What ContentSpiel asks of its host"). A value that is not an address
  # stops the boot here, with a message that names the variable.
  HostSettings.apply(config)

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Mail is SMTP with the site's settings, given to each message by
  # ApplicationMailer from MailSettings (Settings -> Mail, or the host's
  # MAIL_* variables): no smtp_settings here, and no credential in this file
  # or in the credentials. A failure raises and is recorded (MailDeliveryJob).
  config.action_mailer.delivery_method = :smtp

  # Locale fallbacks are not an environment setting: public output falls back
  # along the site's own per-language chain (`Locales.fallback_chain`, read
  # from site_settings at request time), the same in every environment, and
  # Mobility's plain readers deliberately don't fall back at all
  # (config/initializers/mobility.rb).

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]
end
