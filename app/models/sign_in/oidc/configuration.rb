module SignIn
  module Oidc
    # What the provider's discovery document says, as far as sign-in uses
    # it: the endpoints, the scopes it lists and how the client proves itself
    # at the token endpoint (`["client_secret_basic"]` when the document says
    # nothing, as the specification's default).
    #
    # It is cached as `to_h` (strings, arrays of strings) and built again
    # from that, never cached as this object, so a cache entry holds JSON's
    # own types. An entry is built with exactly these members, so one
    # written before a member was added or removed would raise in
    # `from_cache`: the cache key carries CACHE_VERSION, and a change of the
    # members bumps it, so after a deploy the old entries are never read
    # and the document is fetched again.
    Configuration = Data.define(:issuer, :authorization_endpoint, :token_endpoint, :jwks_uri, :scopes_supported, :token_auth_methods) do
      # Bumped with every change of the members above.
      const_set(:CACHE_VERSION, 1)

      def self.from_cache(hash) = new(**hash.symbolize_keys)

      # Whether the provider lists `offline_access`, without which it would
      # refuse the scope (Google does) and gives no refresh token.
      def offline_access? = scopes_supported.include?("offline_access")
    end
  end
end
