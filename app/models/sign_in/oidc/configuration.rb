module SignIn
  module Oidc
    # What the provider's discovery document says, as far as sign-in uses
    # it: the endpoints, the scopes it lists and how the client proves itself
    # at the token endpoint (`["client_secret_basic"]` when the document says
    # nothing, as the specification's default).
    #
    # It is cached as `to_h` (strings, arrays of strings) and built again
    # from that, never cached as this object, so a cache entry holds JSON's
    # own types and outlives a change to this class.
    Configuration = Data.define(:issuer, :authorization_endpoint, :token_endpoint, :jwks_uri, :scopes_supported, :token_auth_methods) do
      def self.from_cache(hash) = new(**hash.symbolize_keys)

      # Whether the provider lists `offline_access`, without which it would
      # refuse the scope (Google does) and gives no refresh token.
      def offline_access? = scopes_supported.include?("offline_access")
    end
  end
end
