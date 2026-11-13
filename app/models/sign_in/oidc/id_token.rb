module SignIn
  module Oidc
    # An ID token's claims, once its signature and its claims are checked:
    # the one check of an ID token, for the sign-in's code exchange
    # (`Callback`) and the daily re-check's refresh (`Refresh`).
    #
    # THE SIGNATURE. The token is a compact JWS of three parts whose header
    # and payload are JSON objects; anything else (a JWE, junk) is refused
    # before json-jwt sees it, since json-jwt answers some junk with a
    # `NoMethodError`. Its `alg` is one of ALGORITHMS, asymmetric only:
    # `none` would be no signature, and an HS* token would be checked with a
    # key json-jwt took from the provider's public set (or forged with the
    # client secret, which the provider shares). A `crit` header is refused,
    # since json-jwt understands no extension (RFC 7515, 4.1.11). The key is
    # the one the header's `kid` names in the provider's set, of the type and
    # curve the `alg` needs, never one the token carries (`jwk`, `jku`,
    # `x5u` are not read); a `kid` the cached set lacks reads the set again
    # once (`keys(refresh: true)`, a provider's key rotation).
    #
    # A TOKEN WITH NO `kid` IS REFUSED, even when the provider's set holds a
    # single key. Without a `kid` the key would have to be guessed from the
    # set, and the guess would change under a rotation: while the provider
    # serves the old key beside the new one, the set holds two and a token
    # that verified yesterday would be refused for a reason nobody could
    # read. Okta, Entra ID, Google, Keycloak and Auth0 all send `kid`, so
    # the rule costs nothing for the providers sign-in is built for.
    #
    # THE CLAIMS are checked here, not by the gem's
    # `OpenIDConnect::ResponseObject::IdToken#verify!`, which compares the
    # nonce with `==` and, when none is expected, refuses a token that
    # carries one (OpenID Connect Core 12.2 lets a refreshed token repeat
    # the sign-in's); gives `exp` no leeway; reads neither `azp` nor `iat`;
    # and turns every claim into a string first, so a `sub` of `12` would
    # pass as "12". Here:
    #
    # - `iss` is exactly the configured issuer;
    # - `sub` is a string of 1 to 255 characters (the specification's limit);
    # - `aud` is the client id or an array holding it, and with several
    #   audiences, or any `azp`, `azp` is the client id;
    # - `exp` is a number not more than LEEWAY in the past, and `iat` a
    #   number not more than LEEWAY in the future: LEEWAY is the clock skew
    #   between this server and the provider's that a token is allowed;
    # - `iat` is not more than MAX_AGE plus LEEWAY in the past: a token is
    #   used the moment the token endpoint issues it, so an old one is a
    #   replay, whatever its `exp` says (a provider may give an ID token a
    #   lifetime of hours);
    # - `nonce` is the kept one, compared with `secure_compare`, unless the
    #   caller passes NONCE_NOT_CHECKED (the refresh, which keeps no nonce).
    #
    # Every refusal is `Refused`, with fixed words; no message names the
    # token or a claim, since a message reaches a span's exception event and
    # an error page.
    module IdToken
      LEEWAY = 60.seconds
      MAX_AGE = 10.minutes
      ALGORITHMS = %w[RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512].freeze
      # The key type each algorithm needs, and for ES* the curve.
      KEY_FOR = {
        "RS" => { "kty" => "RSA" }, "PS" => { "kty" => "RSA" },
        "ES256" => { "kty" => "EC", "crv" => "P-256" }, "ES384" => { "kty" => "EC", "crv" => "P-384" },
        "ES512" => { "kty" => "EC", "crv" => "P-521" }
      }.freeze
      MAX_SUBJECT = 255
      NONCE_NOT_CHECKED = :nonce_not_checked

      class Refused < StandardError
        def initialize(message = "an ID token that could not be verified") = super
      end

      # What a token from outside may make json-jwt or OpenSSL raise while
      # it is decoded and its signature checked.
      DECODE_ERRORS = [ JSON::JWT::Exception, JSON::ParserError, EncodingError, ArgumentError, KeyError, OpenSSL::OpenSSLError ].freeze

      # The verified claims, a Hash of string keys; raises `Refused`, or
      # `Unavailable` when the provider's keys cannot be read.
      def self.verify(token, provider:, nonce:)
        unless nonce == NONCE_NOT_CHECKED || (nonce.is_a?(String) && !nonce.empty?)
          raise ArgumentError, "nonce: is the kept nonce, or NONCE_NOT_CHECKED"
        end

        claims = signed_claims(token, provider)
        check_claims(claims, provider: provider, nonce: nonce)
        claims
      end

      def self.signed_claims(token, provider)
        raise Refused unless token.is_a?(String) && token.count(".") == 2

        header = json_object(token.split(".", 3).first)
        payload = json_object(token.split(".", 3).second)
        alg = header["alg"]
        raise Refused unless ALGORITHMS.include?(alg) && !header.key?("crit") && header["kid"].is_a?(String)

        key = key_for(provider.keys, header) || key_for(provider.keys(refresh: true), header)
        raise Refused unless key

        JSON::JWT.decode(token, key, [ alg.to_sym ])
        payload
      rescue *DECODE_ERRORS
        raise Refused
      end

      # The JSON object a base64url segment holds; raises `Refused`.
      def self.json_object(segment)
        value = JSON.parse(Base64.urlsafe_decode64(segment))
        raise Refused unless value.is_a?(Hash)

        value
      end

      # The key in `set` the header's `kid` names, when it fits the `alg`
      # and is not marked for another use or algorithm.
      def self.key_for(set, header)
        alg = header["alg"]
        needs = KEY_FOR.fetch(alg.start_with?("ES") ? alg : alg.first(2))
        set.find do |key|
          key[:kid] == header["kid"] && needs.all? { |name, value| key[name] == value } &&
            (key[:use].nil? || key[:use] == "sig") && (key[:alg].nil? || key[:alg] == alg)
        end
      end

      def self.check_claims(claims, provider:, nonce:)
        now = Time.current.to_i
        raise Refused unless claims["iss"].is_a?(String) && claims["iss"] == provider.issuer

        subject = claims["sub"]
        raise Refused unless subject.is_a?(String) && !subject.empty? && subject.length <= MAX_SUBJECT

        audiences = claims["aud"].is_a?(String) ? [ claims["aud"] ] : claims["aud"]
        raise Refused unless audiences.is_a?(Array) && audiences.all?(String) && audiences.include?(provider.client_id)
        raise Refused if (audiences.size > 1 || claims.key?("azp")) && claims["azp"] != provider.client_id

        raise Refused unless claims["exp"].is_a?(Numeric) && claims["exp"] > now - LEEWAY.to_i
        raise Refused unless claims["iat"].is_a?(Numeric) && claims["iat"] <= now + LEEWAY.to_i
        raise Refused if claims["iat"] < now - (MAX_AGE + LEEWAY).to_i

        return if nonce == NONCE_NOT_CHECKED

        given = claims["nonce"]
        raise Refused unless given.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(given, nonce)
      end

      private_class_method :signed_claims, :json_object, :key_for, :check_claims
    end
  end
end
