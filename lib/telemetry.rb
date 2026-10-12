# What `config/initializers/opentelemetry.rb` decides with, kept apart from
# it so the decision can be tested as a table without booting four times.
#
# `config/application.rb` requires this file and `telemetry/path_scrubber`
# itself although `lib/` is autoloaded (`config.autoload_lib`): an
# initializer hands the scrubber's objects to the OpenTelemetry SDK, which
# keeps them for the life of the process, so they are loaded once, before
# the autoloader is set up, and are not among what a development reload
# takes away and defines again.
module Telemetry
  ENDPOINT = "OTEL_EXPORTER_OTLP_ENDPOINT".freeze
  CONSOLE = "OTEL_CONSOLE".freeze

  # Where the spans of this process go, first match first:
  #
  #   :memory   the test environment, whatever is set
  #   :otlp     an endpoint is configured
  #   :console  somebody asked for the spans in the terminal: OTEL_CONSOLE=1
  #   :none     everything else, production included. No telemetry at all.
  #
  # `:none` is the default ON PURPOSE. It used to be `:console`, and a
  # production container with no endpoint printed every span to its log:
  # about 49,000 lines for 60 requests, with the path of every request in
  # them, a password-reset token included. Printing is asked for by its own
  # variable and by the one value "1", so that no environment prints because
  # something else was left unset.
  #
  # `env` is anything that answers `[]` with a string or nil (`ENV`, a Hash);
  # `rails_env` is `Rails.env` or its name.
  def self.exporter_kind(env, rails_env)
    return :memory if rails_env.to_s == "test"
    return :otlp unless env[ENDPOINT].to_s.strip.empty?
    return :console if env[CONSOLE] == "1"

    :none
  end
end
