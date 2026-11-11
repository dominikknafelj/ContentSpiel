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
  # WHAT PASSES. Cloudflare's `success`, for a token solved on this site's
  # host (`hostname`, compared with the request's host the caller hands in)
  # and by the sign-in widget (`action`, ACTION, which the widget's markup
  # reads too). A token the same site key minted on another host (a staging
  # copy, a second site sharing the key) or by another widget is `:failed`.
  #
  # FAILING OPEN. When Cloudflare cannot be reached, answers other than 200,
  # sends something that is no JSON object, or refuses for a reason of the
  # site's and not the visitor's (any code but USER_CODES: `internal-error`,
  # and a mistyped or missing secret, `invalid-input-secret`,
  # `missing-input-secret`, `bad-request`), the answer is `:unavailable` and
  # the caller goes on as if the check passed: one line, `[ContentSpiel] The
  # bot check could not be verified: <class, status or code>`, and the
  # span's `auth.bot_check.result` say so. A provider's outage or a host's
  # wrong key must not lock an owner out of their own site, the line shows
  # the host what to fix, and the throttles still stand without the check.
  # A refusal for the visitor's token (USER_CODES: a wrong, expired or
  # replayed token) is `:failed`. Any other error raises: it is a bug.
  #
  # A token that is no String, is blank or is over TOKEN_MAX characters is
  # `:failed` without asking Cloudflare: a bot's junk costs no outside call.
  #
  # THE SECRET AND THE TOKEN ARE NEVER LOGGED, nor put in a span: the log
  # line and `error.type` name a class, a status or a code, and the request runs
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
    # The widget's action, rendered with the widget and required back.
    ACTION = "sign_in".freeze
    # Siteverify's codes that refuse the visitor's token. Every other code
    # is the site's or Cloudflare's own failure, and says nothing of the
    # visitor.
    USER_CODES = %w[invalid-input-response timeout-or-duplicate].freeze
    # A code is logged as Cloudflare spells its codes, or not at all.
    CODE = /\A[a-z][a-z-]{0,63}\z/

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

      answer = JSON.parse(response.body.to_s)
      raise Unavailable, "an answer that is no JSON object" unless answer.is_a?(Hash)

      answer
    end

    def initialize(site_key:, secret_key:)
      @site_key = site_key
      @secret_key = secret_key
    end

    # :passed, :failed or :unavailable (which the caller treats as passed).
    # `hostname` is the request's host.
    def verify(token, address:, hostname:)
      return :failed unless token.is_a?(String) && token.present? && token.length <= TOKEN_MAX

      Telemetry.in_span("auth.bot_check", kind: :client, attributes: { "server.address" => SERVER }) do |span|
        answer = self.class.siteverify({ "secret" => @secret_key, "response" => token, "remoteip" => address }.compact)
        site_codes = Array(answer["error-codes"]) - USER_CODES
        if answer["success"] == true && ours?(answer, hostname)
          Telemetry.record(span, "auth.bot_check.result" => "passed", "http.response.status_code" => 200)
          :passed
        elsif answer["success"] != true && site_codes.any?
          code = site_codes.first
          unavailable(span, code.is_a?(String) && code.match?(CODE) ? code : "an unknown error code", "http.response.status_code" => 200)
        else
          Telemetry.record(span, "auth.bot_check.result" => "failed", "http.response.status_code" => 200)
          :failed
        end
      rescue Unavailable, *NETWORK_ERRORS => error
        unavailable(span, OutsideCall.describe(error), OutsideCall.failure_attributes(error, "auth.bot_check.result"))
      end
    end

    private

    def ours?(answer, hostname)
      answer["hostname"].is_a?(String) && hostname.is_a?(String) &&
        answer["hostname"].casecmp?(hostname) && answer["action"] == ACTION
    end

    def unavailable(span, described, attributes)
      Rails.logger.warn("[ContentSpiel] The bot check could not be verified: #{described}")
      Telemetry.record(span, { "auth.bot_check.result" => "unavailable", "error.type" => described }.merge(attributes))
      :unavailable
    end
  end
end
