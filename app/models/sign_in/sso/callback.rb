module SignIn
  module Sso
    # The provider's answer to a sign-in: the callback's parameters checked
    # against the state kept in the browser's cookie, the code exchanged at
    # the token endpoint, and the ID token verified (`SignIn::Sso::IdToken`),
    # answering who the provider says signed in.
    #
    # `call(params:, kept:)` answers a `Result`: `ok` with the `Identity`, or
    # a `reason`, one of `UNFINISHED_REASONS`, in this order:
    #
    # 1. an `error` from the provider: `cancelled` for `access_denied` (the
    #    person said no), `provider_error` for any other;
    # 2. `bad_state`: no kept state (or one missing its nonce or verifier),
    #    a `state` that is not the kept one, or no `code`. A parameter that
    #    is no string (`state[]=`, `code[a]=`) counts as none, so a Hash or
    #    an Array never reaches `secure_compare`. Nothing is sent to the
    #    provider for any of them;
    # 3. the token request, a POST of the code, the redirect URI and the
    #    PKCE verifier (`Provider#post_token`), under an `auth.sso.token`
    #    CLIENT span: `unavailable` when the provider cannot be reached,
    #    answers 500 or more, or answers more than MAX_BODY; `provider_error`
    #    for another status than 200;
    # 4. `bad_token`: an answer with no ID token, or one that does not
    #    verify; `unavailable` when the keys cannot be read.
    #
    # A REASON IS A WORD, NEVER THE PROVIDER'S MESSAGE. A provider's
    # `error_description`, and anything else in its answer, is text from
    # outside: it reaches no span, log line or page, and a page draws the
    # reason's own sentence. Likewise nothing the browser sent (the code,
    # the state) and nothing kept (the nonce, the verifier) is put in a span
    # or a message.
    #
    # It never raises for anything the provider or the browser sends.
    class Callback
      # The longest email an Identity carries (an address's limit, RFC 5321).
      MAX_EMAIL = 254

      Result = Data.define(:ok, :identity, :reason) do
        def self.refused(reason) = new(ok: false, identity: nil, reason: reason)
      end

      def initialize(provider:, redirect_uri:)
        @provider = provider
        @redirect_uri = redirect_uri
      end

      def inspect = "#<#{self.class.name} issuer_host=#{provider.issuer_host.inspect}>"
      alias_method :to_s, :inspect

      def call(params:, kept:)
        error = params["error"]
        return Result.refused(error == "access_denied" ? "cancelled" : "provider_error") unless error.nil? || error == ""

        code = params["code"]
        return Result.refused("bad_state") unless kept_whole?(kept) && state_matches?(params["state"], kept["state"]) && word?(code)

        exchanged = exchange(code, kept["verifier"])
        return Result.refused(exchanged) if exchanged.is_a?(String)

        identity(exchanged, kept["nonce"])
      rescue Unavailable
        Result.refused("unavailable")
      end

      private
        attr_reader :provider, :redirect_uri

        def kept_whole?(kept)
          kept.is_a?(Hash) && %w[state nonce verifier].all? { |name| word?(kept[name]) }
        end

        # THE ONE COMPARISON OF THE STATE. The controller's `take_sso_state`
        # only reads the cookie, checks its age and spends it; whether the
        # provider sent back this browser's state is decided here, in
        # constant time, so a forged callback learns nothing of the state
        # from how long its refusal took.
        def state_matches?(given, kept)
          word?(given) && ActiveSupport::SecurityUtils.secure_compare(given, kept)
        end

        def word?(value) = value.is_a?(String) && !value.empty?

        # The token endpoint's 200 `TokenAnswer`, or the reason word.
        # Raises `Unavailable` when discovery cannot be read.
        def exchange(code, verifier)
          configuration = provider.configuration
          form = { "grant_type" => "authorization_code", "code" => code, "redirect_uri" => redirect_uri, "code_verifier" => verifier }
          Telemetry.in_span("auth.sso.token", kind: :client, attributes: { "server.address" => URI(configuration.token_endpoint).host.to_s }) do |span|
            answer = provider.post_token(form, configuration)
            if answer.status != 200
              Telemetry.record(span, "error.type" => answer.status.to_s, "http.response.status_code" => answer.status)
              next answer.status >= 500 ? "unavailable" : "provider_error"
            end

            Telemetry.record(span, "auth.sso.refresh_token" => !refresh_token(answer.body).nil?)
            answer
          rescue Unavailable => error
            Telemetry.record(span, "error.type" => Sso.error_type(error))
            "unavailable"
          end
        end

        def identity(answer, nonce)
          body = answer.body
          return Result.refused("bad_token") unless body && body["id_token"].is_a?(String)

          claims = IdToken.verify(body["id_token"], provider: provider, nonce: nonce)
          email = claims["email"]
          Result.new(ok: true, reason: nil, identity: Identity.new(
            issuer: provider.issuer, subject: claims["sub"],
            email: (email if email.is_a?(String) && email.length <= MAX_EMAIL),
            # Literally `true`: a provider that sends the string "true" has
            # not said it verified the address. Whether an unverified email
            # may match an account is `SignIn::Sso::Admit`'s to decide.
            email_verified: claims["email_verified"] == true,
            name: (claims["name"] if claims["name"].is_a?(String)),
            refresh_token: refresh_token(body)
          ))
        rescue IdToken::Refused
          Result.refused("bad_token")
        end

        def refresh_token(body)
          token = body&.dig("refresh_token")
          token if word?(token)
        end
    end
  end
end
