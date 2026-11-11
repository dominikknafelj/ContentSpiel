require "digest"

module SignIn
  # Whether a password a person sets is in Have I Been Pwned's list of
  # leaked passwords, asked through its range API (k-anonymity).
  #
  # WHAT LEAVES THE PROCESS: five hex characters, the first of the
  # password's upper-case SHA-1, in the request's path. The answer is every
  # listed suffix under that prefix with its count, padded with lines of
  # count 0 (`Add-Padding: true`) so its size says nothing either; the
  # remaining 35 characters are compared here. Neither the password nor any
  # part of its hash is logged or put in a span.
  #
  # WHY UNTRACED. The Net::HTTP instrumentation's own span would record the
  # path, `/range/ABCDE`, which is part of the hash; `range` runs untraced
  # (`SignIn::OutsideCall`) and `check` records its own CLIENT span with
  # fixed words only.
  #
  # FAILING OPEN. A status other than 200, one of NETWORK_ERRORS, or a body
  # that is not lines of `HEX:DIGITS` (a captive portal's page at 200) is
  # `:unavailable`: the caller accepts the password, and one line says why,
  # `[ContentSpiel] The leaked-password check could not be made: <class or
  # status>`. An outage of the service must not stop a person setting a
  # password. Any other error raises: it is a bug.
  #
  # ON IN PRODUCTION. LEAKED_PASSWORD_CHECK=off turns it off and `on` turns
  # it on, in any environment; unset or blank, it is on in production and
  # off elsewhere, so development's seeded password and the tests never ask
  # the network. Any other value is on: a misspelt switch must not turn a
  # security check off.
  module LeakedPassword
    RANGE_URL = "https://api.pwnedpasswords.com/range/".freeze
    SERVER = "api.pwnedpasswords.com".freeze
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 3
    NETWORK_ERRORS = [
      Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError,
      Net::HTTPBadResponse
    ].freeze
    PREFIX = /\A[0-9A-F]{5}\z/
    LINE = /\A([0-9A-F]{35}):(\d+)\z/

    class Unavailable < OutsideCall::Unavailable; end

    # :leaked, :clean, :unavailable (which the caller treats as clean) or
    # :off.
    def self.check(password, env: ENV)
      return :off unless on?(env)

      digest = Digest::SHA1.hexdigest(password).upcase
      Telemetry.in_span("auth.leaked_password", kind: :client, attributes: { "server.address" => SERVER }) do |span|
        result = listed?(range(digest[0, 5]), digest[5..]) ? :leaked : :clean
        Telemetry.record(span, "auth.leaked_password.result" => result.to_s, "http.response.status_code" => 200)
        result
      rescue Unavailable, *NETWORK_ERRORS => error
        Rails.logger.warn("[ContentSpiel] The leaked-password check could not be made: #{OutsideCall.describe(error)}")
        Telemetry.record(span, OutsideCall.failure_attributes(error, "auth.leaked_password.result"))
        :unavailable
      end
    end

    # The range's body for `prefix`: the one network call, untraced. Raises
    # `Unavailable` on a status other than 200, and one of NETWORK_ERRORS
    # when the call fails. Anything but five upper-case hex characters is
    # refused before it can be sent.
    def self.range(prefix, url: RANGE_URL)
      raise ArgumentError, "a range prefix is five upper-case hex characters" unless prefix.is_a?(String) && prefix.match?(PREFIX)

      uri = URI.join(url, prefix)
      request = Net::HTTP::Get.new(uri)
      request["Add-Padding"] = "true"
      response = OutsideCall.perform(uri, request, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
      raise Unavailable.status(response.code) unless response.code == "200"

      response.body.to_s
    end

    # Whether the check is switched on (see ON IN PRODUCTION above): a
    # caller asks this before paying for anything it does only to look up.
    def self.on?(env = ENV)
      case env["LEAKED_PASSWORD_CHECK"].to_s.strip
      when "off" then false
      when "" then Rails.env.production?
      else true
      end
    end

    # Whether `suffix` is listed with a count above 0. A body with a line of
    # another shape, or none, is no range answer.
    def self.listed?(body, suffix)
      lines = body.split(/\r?\n/).reject(&:empty?)
      matches = lines.map { |line| LINE.match(line) }
      raise Unavailable, "an answer that is not the range's lines" if matches.empty? || matches.any?(&:nil?)

      matches.any? { |match| match[1] == suffix && match[2].to_i.positive? }
    end
    private_class_method :listed?
  end
end
