# What `config/initializers/opentelemetry.rb` decides with, kept apart from
# it so the decision can be tested as a table without booting four times.
#
# `config/application.rb` requires this file, `telemetry/path_scrubber` and
# `telemetry/work_sampler` itself although `lib/` is autoloaded
# (`config.autoload_lib`): an initializer hands the scrubber's and the
# sampler's objects to the OpenTelemetry SDK, which keeps them for the life
# of the process, so they are loaded once, before
# the autoloader is set up, and are not among what a development reload
# takes away and defines again.
module Telemetry
  # Either says where the spans go. The OTLP exporter reads both by itself,
  # the traces' own ahead of the general one, so somebody who set only that
  # one has configured an endpoint and must not get silence for it.
  ENDPOINTS = %w[OTEL_EXPORTER_OTLP_TRACES_ENDPOINT OTEL_EXPORTER_OTLP_ENDPOINT].freeze
  CONSOLE = "OTEL_CONSOLE".freeze

  # Where the spans of this process go, first match first:
  #
  #   :memory   the test environment, whatever is set
  #   :otlp     an endpoint is configured (either of ENDPOINTS, not blank)
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
    return :otlp if ENDPOINTS.any? { |name| !env[name].to_s.strip.empty? }
    return :console if env[CONSOLE] == "1"

    :none
  end
end
