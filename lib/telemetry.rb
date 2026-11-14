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

  # The CMS's own spans and the attributes they may carry. A span is started
  # through `in_span` and written through it or `record`, and both refuse a
  # name or a key that is not here, so a new span or attribute is named in
  # this file or it fails (`test/lib/telemetry_spans_test.rb` holds that no
  # other file starts a span). The lists carry names only: what a value may be
  # (a fixed word, a number or a Boolean, never text that came in a request:
  # an email, a password or a part of its hash, a token) is held by the tests
  # that plant such text and search every exported span for it.
  #
  # None of these is a root. `Telemetry::WorkSampler` drops an INTERNAL or a
  # CLIENT root with its whole trace, so each is recorded only as a child of
  # a request's SERVER span or a job's CONSUMER span; started anywhere else
  # it is a no-op, as every span is when the SDK is not configured.
  SPANS = %w[
    auth.sign_in
    auth.throttle
    auth.bot_check
    auth.leaked_password
    auth.lockout_mail
    auth.session
    auth.session_sweep
    auth.passkey
    auth.recovery_code
    auth.second_factor
    auth.confirmation
    auth.account_mail
    auth.sso.redirect
    auth.sso.callback
    auth.sso.discovery
    auth.sso.token
    auth.sso.recheck
    auth.sso.recheck_run
  ].freeze

  ATTRIBUTES = %w[
    auth.method
    auth.outcome
    auth.account_exists
    auth.bucket
    auth.tripped
    auth.backoff_level
    auth.bot_check.required
    auth.bot_check.result
    auth.leaked_password.result
    auth.mail.queued
    auth.session.reason
    auth.session.count
    auth.passkey.ceremony
    auth.policy
    auth.second_factor.required
    auth.mail.kind
    auth.sso.intent
    auth.sso.reason
    auth.sso.cached
    auth.sso.refresh_token
    auth.sso.issuer_host
    auth.sso.recheck.checked
    auth.sso.recheck.ok
    auth.sso.recheck.revoked
    auth.sso.recheck.unavailable
    auth.refused_by_rule
    server.address
    http.response.status_code
    error.type
  ].freeze

  # The API's provider is a proxy until `config/initializers/opentelemetry.rb`
  # configures the SDK, and a tracer it handed out delegates from then on, so
  # one memoised before that still records; with no SDK at all it stays the
  # API's no-op.
  def self.tracer
    @tracer ||= OpenTelemetry.tracer_provider.tracer("contentspiel", ContentSpiel::VERSION)
  end

  # The block's value, inside a span `name` of `kind`, a child of the current
  # span. `tracer` is for a test that needs a provider of its own. The SDK
  # records whatever kind it is handed, so a misspelt one is refused here
  # rather than sent.
  def self.in_span(name, kind: :internal, attributes: {}, tracer: self.tracer, &block)
    check_span(name, kind, attributes)
    tracer.in_span(name, kind: kind, attributes: attributes, &block)
  end

  # Like `in_span`, but only inside a span that records: with none (the
  # cable's connect, which runs on Action Cable's worker pool outside any
  # request's span) the block runs with no span, since one started there
  # would be a root the work sampler drops. The block is handed the span, or
  # nil.
  def self.in_child_span(name, kind: :internal, attributes: {}, &block)
    return in_span(name, kind: kind, attributes: attributes, &block) if OpenTelemetry::Trace.current_span.recording?

    check_span(name, kind, attributes)
    block.call(nil)
  end

  # Adds `attributes` to `span`, and answers the span.
  def self.record(span, attributes)
    check_keys(attributes)
    span.add_attributes(attributes)
    span
  end

  # A name from SPANS, a kind the API knows and keys from ATTRIBUTES, checked
  # whether or not a span is started, so a misspelling fails everywhere.
  def self.check_span(name, kind, attributes)
    raise ArgumentError, "#{name.inspect} is not among Telemetry::SPANS" unless SPANS.include?(name)
    raise ArgumentError, "#{kind.inspect} is not a span kind" unless span_kinds.include?(kind)
    check_keys(attributes)
  end

  def self.check_keys(attributes)
    unlisted = attributes.keys.reject { |key| ATTRIBUTES.include?(key) }
    return if unlisted.empty?

    raise ArgumentError, "#{unlisted.map(&:inspect).join(", ")} not among Telemetry::ATTRIBUTES"
  end

  # :internal, :server, :client, :producer and :consumer, read from the API.
  def self.span_kinds
    OpenTelemetry::Trace::SpanKind.constants.map { |name| OpenTelemetry::Trace::SpanKind.const_get(name) }
  end
  private_class_method :check_span, :check_keys, :span_kinds
end
