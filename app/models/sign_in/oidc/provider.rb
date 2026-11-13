module SignIn
  module Oidc
    # The site's one OpenID Connect provider, from five variables.
    #
    # WHOLE OR NOTHING. `current` is a provider only when SSO_ISSUER,
    # SSO_CLIENT_ID, SSO_CLIENT_SECRET and SSO_NAME are all set and not blank.
    # Some but not all is no single sign-on, and production's boot says which
    # are missing (`missing_variables`, `config/initializers/sign_in.rb`),
    # by name and never a value.
    #
    # THREE THINGS STOP THE BOOT (`check!`, `Misconfigured`, in every
    # environment), since each would silently open what the host meant to
    # close or point sign-in at the wrong place: SSO_REQUIRED without a whole
    # provider; SSO_REQUIRED with a value other than `1`; and, once the
    # provider is whole, an SSO_ISSUER that is no absolute https URL with a
    # host (`http` is allowed only to 127.0.0.1, ::1 or localhost, outside
    # production, which is how the tests' fake provider is reached). A message
    # names the variable and never repeats the value, as `SiteAddress` does.
    #
    # THE SECRET is read through one private method. `inspect` and `to_s` show
    # the issuer's host alone, so an error page or a console never prints it.
    #
    # DISCOVERY AND KEYS. `configuration` reads the issuer's discovery
    # document and `keys` the key set it names, each through
    # `SignIn::OutsideCall` (bounded in time and at MAX_BODY, untraced) under
    # an `auth.sso.discovery` CLIENT span that says whether the answer came
    # from the cache. Each is cached for CACHE_FOR under a key of the
    # issuer's digest, as JSON's own types (`Configuration#to_h`, the key
    # set's hash), so a changed issuer never reads another's entry. An answer
    # that cannot be used raises `SignIn::Oidc::Unavailable` with the System
    # status row's reason (`unreachable`, `http_<status>`, `not_json`,
    # `issuer_mismatch`, `missing_endpoint`) and is never cached, so the next
    # sign-in asks again. A body over MAX_BODY is `not_json`, unread: the
    # provider decides its size, and no document of the specification's comes
    # near it. The document is checked by the openid_connect gem
    # (`OpenIDConnect::Discovery::Provider::Config::Response`): the required
    # members and an issuer that is exactly SSO_ISSUER, since a document
    # naming another issuer would hand sign-in to whoever that is. A token
    # endpoint is required too, which the gem leaves optional.
    #
    # This class is the only reader of the five variables.
    class Provider
      LOOPBACK = %w[127.0.0.1 [::1] localhost].freeze
      WELL_KNOWN = "/.well-known/openid-configuration".freeze
      DEFAULT_TOKEN_AUTH = [ "client_secret_basic" ].freeze

      attr_reader :issuer, :client_id, :name

      def self.current(env = ENV)
        values = read(env)
        new(issuer: values["SSO_ISSUER"], client_id: values["SSO_CLIENT_ID"], secret: values["SSO_CLIENT_SECRET"], name: values["SSO_NAME"]) if values.values.all?
      end

      # The names that are unset or blank when at least one of the four is
      # set; empty with all four or none.
      def self.missing_variables(env = ENV)
        values = read(env)
        values.values.none? || values.values.all? ? [] : values.reject { |_, value| value }.keys
      end

      # Whether single sign-in is required: SSO_REQUIRED is `1` and the
      # provider is whole.
      def self.required?(env = ENV)
        env["SSO_REQUIRED"] == "1" && !current(env).nil?
      end

      # nil, or raises `Misconfigured`.
      def self.check!(env = ENV, production: Rails.env.production?)
        required = env["SSO_REQUIRED"]
        if required.present?
          raise Misconfigured, "SSO_REQUIRED must be 1, or unset." unless required == "1"
          raise Misconfigured, "SSO_REQUIRED is set, but single sign-on is not: set #{VARIABLES[0..-2].join(", ")} and #{VARIABLES.last}." if current(env).nil?
        end
        current(env)&.check_issuer!(production: production)
        nil
      end

      def self.read(env)
        given = env.slice("SSO_ISSUER", "SSO_CLIENT_ID", "SSO_CLIENT_SECRET", "SSO_NAME")
        VARIABLES.index_with { |name| given[name].to_s.strip.presence }
      end
      private_class_method :read

      def initialize(issuer:, client_id:, secret:, name:)
        @issuer = issuer
        @client_id = client_id
        @secret = secret
        @name = name
        freeze
      end

      def issuer_host = uri&.host

      def inspect = "#<#{self.class.name} issuer_host=#{issuer_host.inspect}>"
      alias_method :to_s, :inspect

      # ActiveSupport's `Object#as_json` dumps every instance variable, the
      # secret's included: a provider serialises as its issuer's host alone.
      def as_json(*) = { "issuer_host" => issuer_host }

      # The discovery document's endpoints, scopes and client authentication;
      # raises `Unavailable`.
      def configuration
        Configuration.from_cache(cached("discovery", URI(issuer.chomp("/") + WELL_KNOWN)) { |document| discovered(document) })
      end

      # The provider's signing keys; `refresh: true` reads them again past
      # the cache (a token signed by a key the cached set does not hold);
      # raises `Unavailable`.
      def keys(refresh: false)
        JSON::JWK::Set.new(cached("keys", URI(configuration.jwks_uri), refresh: refresh) { |document| key_set(document) }["keys"])
      end

      def check_issuer!(production:)
        parsed = uri
        usable = parsed&.host.present? && parsed.userinfo.nil? && (parsed.scheme == "https" || (parsed.scheme == "http" && !production && LOOPBACK.include?(parsed.host)))
        raise Misconfigured, "SSO_ISSUER must be an absolute https URL with a host (http only to localhost, outside production)." unless usable
      end

      private
        def client_secret = @secret

        # The cached value for `kind`, or `yield`'s value for the document at
        # `uri`, written to the cache.
        def cached(kind, uri, refresh: false)
          key = "content_spiel/oidc/#{kind}/#{Digest::SHA256.hexdigest(issuer)}"
          Telemetry.in_span("auth.sso.discovery", kind: :client, attributes: { "server.address" => uri.host.to_s }) do |span|
            value = Rails.cache.read(key) unless refresh
            Telemetry.record(span, "auth.sso.cached" => !value.nil?)
            next value if value

            yield(document_at(uri)).tap { |fresh| Rails.cache.write(key, fresh, expires_in: CACHE_FOR) }
          rescue Unavailable => error
            Telemetry.record(span, "auth.sso.reason" => error.reason, "error.type" => error_type(error))
            raise
          end
        end

        # The JSON object at `uri`.
        def document_at(uri)
          request = Net::HTTP::Get.new(uri)
          request["Accept"] = "application/json"
          response = OutsideCall.perform(uri, request, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, max_body: MAX_BODY)
          raise Unavailable.status(response.code) unless response.code == "200"

          document = JSON.parse(response.body.to_s)
          raise Unavailable.new("an answer that is no JSON object", reason: "not_json") unless document.is_a?(Hash)

          document
        rescue JSON::ParserError
          raise Unavailable.new("an answer that is no JSON object", reason: "not_json")
        rescue OutsideCall::Unavailable => error
          raise if error.is_a?(Unavailable)

          raise Unavailable.new("a body over the limit", reason: "not_json")
        rescue *NETWORK_ERRORS
          raise Unavailable.new("the provider could not be reached", reason: "unreachable")
        end

        # The document's members sign-in reads, once the gem has checked it
        # against this issuer.
        def discovered(document)
          response = OpenIDConnect::Discovery::Provider::Config::Response.new(document.deep_symbolize_keys)
          response.expected_issuer = issuer
          response.validate!
          raise Unavailable.new("a document with no token endpoint", reason: "missing_endpoint") if response.token_endpoint.blank?

          Configuration.new(
            issuer: response.issuer, authorization_endpoint: response.authorization_endpoint,
            token_endpoint: response.token_endpoint, jwks_uri: response.jwks_uri,
            scopes_supported: words(response.scopes_supported),
            token_auth_methods: words(response.token_endpoint_auth_methods_supported).presence || DEFAULT_TOKEN_AUTH
          ).to_h.stringify_keys
        rescue OpenIDConnect::ValidationFailed
          mismatch = response.issuer.present? && response.issuer != issuer
          raise Unavailable.new(mismatch ? "a document naming another issuer" : "a document missing a member", reason: mismatch ? "issuer_mismatch" : "missing_endpoint")
        end

        def key_set(document)
          keys = document["keys"]
          raise Unavailable.new("a key set with no keys", reason: "not_json") unless keys.is_a?(Array) && keys.all?(Hash)

          { "keys" => keys }
        end

        def words(value) = Array(value).grep(String)

        # The status, or the network error's class, or the reason.
        def error_type(error)
          return error.status.to_s if error.status
          return error.cause.class.name if error.reason == "unreachable" && error.cause

          error.reason
        end

        def uri
          URI.parse(issuer)
        rescue URI::InvalidURIError
          nil
        end
    end
  end
end
