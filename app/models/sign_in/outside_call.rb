require "net/http"

module SignIn
  # The one HTTPS request a sign-in check makes to an outside service
  # (`SignIn::Protection::BotCheck.siteverify`, `SignIn::LeakedPassword.range`), and how
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
  # BOUNDED. Opening (TCP and TLS) is bounded by the caller's open timeout,
  # each read by its read timeout and each write by the same, and Net::HTTP's
  # one retry of an idempotent request is turned off, or a GET that timed out
  # would wait its timeouts twice. A per-read timeout restarts with every
  # chunk, so a server that drips bytes could still hold the call: the whole
  # call is also cut at the sum of the two (`Timeout.timeout`, raising
  # `Timeout::Error`, which both callers count as unavailable). A sign-in or
  # a password save waits on this, the wizard's under `LOCK TABLE users`.
  # `Timeout.timeout` interrupts the thread wherever it is; inside this block
  # that is Net::HTTP's own I/O, which closes its socket in an `ensure`.
  #
  # BODY-BOUNDED. A caller that names `max_body:` gets an answer whose body is
  # read in chunks and abandoned the moment it passes the figure (a declared
  # `Content-Length` over it is refused before a byte is read), so an outside
  # service cannot make a sign-in hold memory for a body it chose the size of.
  # A caller that names none reads the body whole, as Net::HTTP does.
  module OutsideCall
    AGENT = "ContentSpiel/#{ContentSpiel::VERSION}".freeze

    # An answer that cannot be used: a status other than 200 (`status`), or
    # a body of another shape (the message says which, in fixed words).
    #
    # `reason` is one fixed word saying why (`http_503`, `too_large`, or a
    # caller's own), never a message of anything the service sent.
    class Unavailable < StandardError
      attr_reader :status, :reason

      def self.status(code) = new("HTTP #{code}", status: code.to_i, reason: "http_#{code.to_i}")

      def initialize(message, status: nil, reason: nil)
        super(message)
        @status = status
        @reason = reason
      end
    end

    # The response to `request` (a `Net::HTTPRequest` built for `uri`),
    # within `deadline` seconds in all (the sum of the timeouts unless a
    # test names less).
    def self.perform(uri, request, open_timeout:, read_timeout:, deadline: open_timeout + read_timeout, max_body: nil)
      request["User-Agent"] = AGENT
      OpenTelemetry::Common::Utilities.untraced do
        Timeout.timeout(deadline) do
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
            open_timeout: open_timeout, read_timeout: read_timeout, write_timeout: read_timeout, max_retries: 0) do |http|
            max_body ? bounded(http, request, max_body) : http.request(request)
          end
        end
      end
    end

    # The response, its body read up to `max_body` bytes and no further.
    def self.bounded(http, request, max_body)
      http.request(request) do |response|
        declared = response["Content-Length"]
        raise Unavailable.new("a body over the limit", reason: "too_large") if declared && declared.to_i > max_body

        # The bound counts the body after decoding (a gzip body is inflated by read_body).
        body = +""
        response.read_body do |chunk|
          body << chunk
          raise Unavailable.new("a body over the limit", reason: "too_large") if body.bytesize > max_body
        end
        response.body = body
        return response
      end
    end
    private_class_method :bounded

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
