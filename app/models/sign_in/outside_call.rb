require "net/http"

module SignIn
  # The one HTTPS request a sign-in check makes to an outside service
  # (`SignIn::BotCheck.siteverify`, `SignIn::LeakedPassword.range`), and how
  # its failure is named in a log line and a span.
  #
  # UNTRACED. The request runs inside `OpenTelemetry::Common::Utilities.untraced`,
  # which `opentelemetry-instrumentation-net_http` honours (its `request` and
  # `connect` return `super` when the context is untraced; held by the
  # stub-server tests of both callers): its own CLIENT span would otherwise
  # record the request's path, and the range lookup's path is five characters
  # of a password's SHA-1, which no span may hold. `Telemetry::PathScrubber`
  # cuts queries, not paths. Each caller records the call in a CLIENT span of
  # its own instead, with fixed words only.
  #
  # BOUNDED. Opening (TCP and TLS) and reading are each bounded by the
  # caller's timeouts, writing by the read timeout, and Net::HTTP's one retry
  # of an idempotent request is turned off, or a GET that timed out would
  # wait its timeouts twice. A sign-in or a password save waits on this.
  module OutsideCall
    AGENT = "ContentSpiel/#{ContentSpiel::VERSION}".freeze

    # An answer that cannot be used: a status other than 200 (`status`), or
    # a body of another shape (the message says which, in fixed words).
    class Unavailable < StandardError
      attr_reader :status

      def self.status(code) = new("HTTP #{code}", status: code.to_i)

      def initialize(message, status: nil)
        super(message)
        @status = status
      end
    end

    # The response to `request` (a `Net::HTTPRequest` built for `uri`).
    def self.perform(uri, request, open_timeout:, read_timeout:)
      request["User-Agent"] = AGENT
      OpenTelemetry::Common::Utilities.untraced do
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
          open_timeout: open_timeout, read_timeout: read_timeout, write_timeout: read_timeout, max_retries: 0) do |http|
          http.request(request)
        end
      end
    end

    # What a log line says of `error`: the status, or the class (and, for
    # an answer of the wrong shape, the fixed words saying so). Never a
    # message of another error: an exception's message may quote what was
    # sent or answered.
    def self.describe(error)
      return error.message if error.is_a?(Unavailable) && error.status
      return "#{error.class.name} (#{error.message})" if error.is_a?(Unavailable)

      error.class.name
    end

    # The span's `error.type`: the status as OpenTelemetry names it, or the
    # class.
    def self.error_type(error)
      error.is_a?(Unavailable) && error.status ? error.status.to_s : error.class.name
    end

    # The span's attributes for a failed call.
    def self.failure_attributes(error, result_key)
      { result_key => "unavailable", "error.type" => error_type(error) }
        .merge(error.is_a?(Unavailable) && error.status ? { "http.response.status_code" => error.status } : {})
    end
  end
end
