module SignIn
  # Cloudflare Turnstile, verified on the server: the widget's token is sent
  # to siteverify with the secret and the visitor's address, and Cloudflare
  # says whether a person answered it.
  #
  # ON WITH BOTH KEYS. `current` is a check only when TURNSTILE_SITE_KEY and
  # TURNSTILE_SECRET_KEY are both set and not blank. A site key alone would
  # draw a widget whose answer cannot be verified, and so refuse everyone; a
  # secret alone has no widget to answer. Either one alone is no check, and
  # production's boot names the missing variable (`missing_variable`,
  # `config/initializers/sign_in.rb`), never a value.
  #
  # FAILING OPEN. When Cloudflare cannot be reached, answers other than 200,
  # sends something that is no JSON object, or says `internal-error`, the
  # answer is `:unavailable` and the caller goes on as if the check passed:
  # one line, `[ContentSpiel] The bot check could not be verified: <class or
  # status>`, and the span's `auth.bot_check.result` say so. A provider's
  # outage must not lock an owner out of their own site, and the throttles
  # still stand without the check. Any other error raises: it is a bug.
  #
  # A token that is no String, is blank or is over TOKEN_MAX characters is
  # `:failed` without asking Cloudflare: a bot's junk costs no outside call.
  #
  # THE SECRET AND THE TOKEN ARE NEVER LOGGED, nor put in a span: the log
  # line and `error.type` name a class or a status, and the request runs
  # untraced (`SignIn::OutsideCall`).
  class BotCheck
    VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify".freeze
    SERVER = "challenges.cloudflare.com".freeze
    TOKEN_MAX = 2048
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 3
    NETWORK_ERRORS = [
      Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError,
      Net::HTTPBadResponse, JSON::ParserError
    ].freeze
    # Cloudflare's own failure, which says nothing about the visitor.
    INTERNAL_ERROR = "internal-error".freeze

    class Unavailable < OutsideCall::Unavailable; end

    attr_reader :site_key

    # The check, or nil when either key is unset or blank.
    def self.current(env = ENV)
      site_key = env["TURNSTILE_SITE_KEY"].presence
      secret_key = env["TURNSTILE_SECRET_KEY"].presence
      new(site_key: site_key, secret_key: secret_key) if site_key && secret_key
    end

    # The name of the one key that is unset while the other is set, or nil
    # (both set, or neither: a site that never asked for the check).
    def self.missing_variable(env = ENV)
      site_key = env["TURNSTILE_SITE_KEY"].present?
      secret_key = env["TURNSTILE_SECRET_KEY"].present?
      return if site_key == secret_key

      site_key ? "TURNSTILE_SECRET_KEY" : "TURNSTILE_SITE_KEY"
    end

    # Cloudflare's parsed answer to `form`: the one network call, untraced.
    # Raises `Unavailable` on a status other than 200 or an answer that is no
    # JSON object, and one of NETWORK_ERRORS when the call fails.
    def self.siteverify(form, url: VERIFY_URL)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(form)
      response = OutsideCall.perform(uri, request, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
      raise Unavailable.status(response.code) unless response.code == "200"

      answer = JSON.parse(response.body)
      raise Unavailable, "an answer that is no JSON object" unless answer.is_a?(Hash)

      answer
    end

    def initialize(site_key:, secret_key:)
      @site_key = site_key
      @secret_key = secret_key
    end

    # :passed, :failed or :unavailable (which the caller treats as passed).
    def verify(token, address:)
      return :failed unless token.is_a?(String) && token.present? && token.length <= TOKEN_MAX

      Telemetry.in_span("auth.bot_check", kind: :client, attributes: { "server.address" => SERVER }) do |span|
        answer = self.class.siteverify({ "secret" => @secret_key, "response" => token, "remoteip" => address }.compact)
        if answer["success"] == true
          Telemetry.record(span, "auth.bot_check.result" => "passed", "http.response.status_code" => 200)
          :passed
        elsif Array(answer["error-codes"]).include?(INTERNAL_ERROR)
          unavailable(span, INTERNAL_ERROR, "http.response.status_code" => 200)
        else
          Telemetry.record(span, "auth.bot_check.result" => "failed", "http.response.status_code" => 200)
          :failed
        end
      rescue Unavailable, *NETWORK_ERRORS => error
        unavailable(span, OutsideCall.describe(error), OutsideCall.failure_attributes(error, "auth.bot_check.result"))
      end
    end

    private

    def unavailable(span, described, attributes)
      Rails.logger.warn("[ContentSpiel] The bot check could not be verified: #{described}")
      Telemetry.record(span, { "auth.bot_check.result" => "unavailable", "error.type" => described }.merge(attributes))
      :unavailable
    end
  end
end
