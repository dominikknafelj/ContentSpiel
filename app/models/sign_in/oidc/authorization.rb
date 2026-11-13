module SignIn
  module Oidc
    # The request that sends a person to the provider: the authorization
    # URL, and the three values the callback is checked against.
    #
    # Each `start` makes a fresh state (ties the callback to this browser's
    # cookie), nonce (ties the ID token to this request) and PKCE verifier
    # (ties the code to whoever holds the verifier), each 32 random bytes.
    # Only the S256 challenge of the verifier goes into the URL; the
    # verifier itself is sent once, to the token endpoint.
    #
    # The URL is built by the openid_connect gem
    # (`OpenIDConnect::Client#authorization_uri`), which adds the client id
    # and the redirect URI. `offline_access` is asked for only when the
    # provider lists it: a provider that does not refuses the whole request.
    #
    # THE THREE VALUES ARE SECRETS until the callback spends them, and the
    # URL holds two of them: `inspect`, `to_s` and `as_json` name the
    # endpoint's host alone.
    class Authorization
      SCOPES = %w[openid email profile].freeze

      attr_reader :url, :state, :nonce, :verifier

      # Raises `SignIn::Oidc::Unavailable` when the discovery document
      # cannot be read.
      def self.start(provider:, redirect_uri:)
        configuration = provider.configuration
        state, nonce, verifier = Array.new(3) { SecureRandom.urlsafe_base64(32) }
        client = OpenIDConnect::Client.new(identifier: provider.client_id, redirect_uri: redirect_uri,
          authorization_endpoint: configuration.authorization_endpoint)
        url = client.authorization_uri(
          response_type: "code", scope: SCOPES + (configuration.offline_access? ? [ "offline_access" ] : []),
          state: state, nonce: nonce, code_challenge: challenge(verifier), code_challenge_method: "S256"
        )
        new(url: url, state: state, nonce: nonce, verifier: verifier)
      end

      # RFC 7636's S256: the unpadded base64url of the verifier's SHA-256.
      def self.challenge(verifier) = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

      def initialize(url:, state:, nonce:, verifier:)
        @url = url
        @state = state
        @nonce = nonce
        @verifier = verifier
        freeze
      end

      def inspect = "#<#{self.class.name} endpoint_host=#{endpoint_host.inspect}>"
      alias_method :to_s, :inspect

      # ActiveSupport's `Object#as_json` dumps every instance variable.
      def as_json(*) = { "endpoint_host" => endpoint_host }

      private
        def endpoint_host = URI(url).host
    end
  end
end
