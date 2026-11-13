module SignIn
  module Oidc
    # The daily re-check of an SSO session (`Sso::RecheckJob`): its refresh
    # token sent back to the token endpoint, under an `auth.sso.recheck`
    # CLIENT span whose `auth.outcome` is the answer's status.
    #
    # `call(refresh_token, subject:)` answers a `Result`:
    #
    # - `:ok`, with the token the provider rotated to, or the one given when
    #   it rotated none;
    # - `:revoked`: a 400 `invalid_grant` (the person was removed, or the
    #   grant revoked), or a refreshed ID token that verifies but names
    #   another `sub` than the link's `subject`. The job ends the session;
    # - `:unavailable`: the provider could not be reached, answered 500 or
    #   more, or answered something the re-check cannot read (another
    #   status, a body of the wrong shape, an ID token that does not
    #   verify). The job leaves the session for its next run, and
    #   `Session#expiry` ends it once the grace has passed.
    #
    # ANOTHER REFUSAL IS NOT A REVOCATION. A 401 `invalid_client` (the
    # client secret was changed at the provider) or a 400 other than
    # `invalid_grant` says nothing of the person: read as `:revoked`, one
    # misconfiguration would end every SSO session at once.
    #
    # The refreshed ID token is verified with no nonce
    # (`IdToken::NONCE_NOT_CHECKED`): the re-check keeps none, and OpenID
    # Connect Core 12.2 lets the provider leave it out or repeat the
    # sign-in's.
    #
    # Neither token reaches a span, a log line or the `Result`'s `inspect`.
    class Refresh
      Result = Data.define(:status, :refresh_token) do
        def inspect = "#<#{self.class.name} status=#{status.inspect}>"
        alias_method :to_s, :inspect

        def as_json(*) = { "status" => status.to_s }
      end

      def initialize(provider:)
        @provider = provider
      end

      def inspect = "#<#{self.class.name} issuer_host=#{provider.issuer_host.inspect}>"
      alias_method :to_s, :inspect

      def call(refresh_token, subject:)
        raise ArgumentError, "a refresh token is required" unless refresh_token.is_a?(String) && !refresh_token.empty?

        Telemetry.in_span("auth.sso.recheck", kind: :client) do |span|
          result = recheck(refresh_token, subject, span)
          Telemetry.record(span, "auth.outcome" => result.status.to_s)
          result
        end
      end

      private
        attr_reader :provider

        def recheck(refresh_token, subject, span)
          configuration = provider.configuration
          Telemetry.record(span, "server.address" => URI(configuration.token_endpoint).host.to_s)
          answer = provider.post_token({ "grant_type" => "refresh_token", "refresh_token" => refresh_token }, configuration)
          body = answer.body
          return revoked if answer.status == 400 && body&.dig("error") == "invalid_grant"

          unless answer.status == 200
            Telemetry.record(span, "error.type" => answer.status.to_s, "http.response.status_code" => answer.status)
            return unavailable
          end
          return unavailable(span, "not_json") unless body

          rotated = body["refresh_token"]
          return unavailable(span, "not_json") unless rotated.nil? || (rotated.is_a?(String) && !rotated.empty?)

          id_token = body["id_token"]
          unless id_token.nil?
            return unavailable(span, "not_json") unless id_token.is_a?(String)
            return revoked if IdToken.verify(id_token, provider: provider, nonce: IdToken::NONCE_NOT_CHECKED)["sub"] != subject
          end

          Result.new(status: :ok, refresh_token: rotated || refresh_token)
        rescue Unavailable => error
          Telemetry.record(span, "error.type" => Oidc.error_type(error))
          unavailable
        rescue IdToken::Refused
          unavailable(span, "bad_token")
        end

        def revoked = Result.new(status: :revoked, refresh_token: nil)

        def unavailable(span = nil, reason = nil)
          Telemetry.record(span, "auth.sso.reason" => reason, "error.type" => reason) if span && reason
          Result.new(status: :unavailable, refresh_token: nil)
        end
    end
  end
end
