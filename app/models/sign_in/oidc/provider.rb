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
      # The members of a public signing key of each type sign-in checks ID
      # tokens with, and the labels kept beside them.
      KEY_MEMBERS = { "RSA" => %w[kty n e], "EC" => %w[kty crv x y] }.freeze
      KEY_LABELS = %w[kid use alg].freeze

      # The token endpoint's answer: its status, and its body when that is a
      # JSON object (nil when it is anything else). The body holds tokens, so
      # `inspect` and `as_json` say the status alone.
      TokenAnswer = Data.define(:status, :body) do
        def inspect = "#<#{self.class.name} status=#{status}>"
        alias_method :to_s, :inspect

        def as_json(*) = { "status" => status }
      end

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
      #
      # They are cached under the issuer, not under `jwks_uri`, as the
      # document is: a provider that moves its key set is read at the new
      # address within CACHE_FOR, when the document's entry ends, or at once
      # when a token arrives signed by a `kid` the cached set lacks and the
      # caller asks again with `refresh: true`.
      def keys(refresh: false)
        JSON::JWK::Set.new(cached("keys", URI(configuration.jwks_uri), refresh: refresh) { |document| key_set(document) }["keys"])
      end

      # The token endpoint's `TokenAnswer` to `form` (a code or a refresh
      # grant), the endpoint read from `configuration` (the caller's, so the
      # discovery span is not nested in the caller's token span). Raises
      # `Unavailable` when the endpoint cannot be reached (`unreachable`) or
      # answers more than MAX_BODY (`too_large`), unread.
      #
      # The client proves itself with client_secret_basic, the
      # specification's default, or client_secret_post when that is the
      # only method the document lists: a provider listing neither is sent
      # Basic, and its refusal is its answer. Basic's id and secret are each
      # form-encoded first (RFC 6749, 2.3.1), so a secret holding a `:` is
      # read whole.
      #
      # The secret reaches the request and nothing else: `Net::HTTPRequest#inspect`
      # names the method alone, and nothing here is logged or put in a span.
      def post_token(form, configuration)
        uri = URI(configuration.token_endpoint)
        request = Net::HTTP::Post.new(uri)
        request["Accept"] = "application/json"
        if configuration.token_auth_methods == [ "client_secret_post" ]
          form = form.merge("client_id" => client_id, "client_secret" => client_secret)
        else
          pair = [ client_id, client_secret ].map { |part| URI.encode_www_form_component(part) }.join(":")
          request["Authorization"] = "Basic #{Base64.strict_encode64(pair)}"
        end
        request.set_form_data(form)
        response = OutsideCall.perform(uri, request, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, max_body: MAX_BODY)
        TokenAnswer.new(status: response.code.to_i, body: json_object(response.body))
      rescue OutsideCall::Unavailable
        raise Unavailable.new("a body over the limit", reason: "too_large")
      rescue *NETWORK_ERRORS
        raise Unavailable.new("the provider could not be reached", reason: "unreachable")
      end

      def check_issuer!(production:)
        usable = self.class.secure_address?(uri, production: production) && uri.userinfo.nil?
        raise Misconfigured, "SSO_ISSUER must be an absolute https URL with a host (http only to localhost, outside production)." unless usable
      end

      # The one rule for every address sign-in talks to the provider at (the
      # issuer and the three endpoints its document names): an absolute URL
      # with a host, https, or http only to the loopback outside production.
      # The token endpoint is sent the client secret, the code and the PKCE
      # verifier, and the key set decides which ID tokens are believed, so an
      # http endpoint from an https issuer would hand both to anyone on the
      # path.
      def self.secure_address?(uri, production: Rails.env.production?)
        uri.is_a?(URI::Generic) && uri.host.present? &&
          (uri.scheme == "https" || (uri.scheme == "http" && !production && LOOPBACK.include?(uri.host)))
      end

      private
        def client_secret = @secret

        # The cached value for `kind`, or `yield`'s value for the document at
        # `uri`, written to the cache.
        def cached(kind, uri, refresh: false)
          key = "content_spiel/oidc/#{kind}/#{Digest::SHA256.hexdigest(issuer)}"
          key = "#{key}/v#{Configuration::CACHE_VERSION}" if kind == "discovery"
          Telemetry.in_span("auth.sso.discovery", kind: :client, attributes: { "server.address" => uri.host.to_s }) do |span|
            value = Rails.cache.read(key) unless refresh
            Telemetry.record(span, "auth.sso.cached" => !value.nil?)
            next value if value

            yield(document_at(uri)).tap { |fresh| Rails.cache.write(key, fresh, expires_in: CACHE_FOR) }
          rescue Unavailable => error
            Telemetry.record(span, "auth.sso.reason" => error.reason, "error.type" => Oidc.error_type(error))
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
        #
        # Each refusal has its fixed words, and its reason is one of the
        # System status row's, which are a fixed set: a document naming
        # another issuer, or none, is `issuer_mismatch`; one missing a member sign-in
        # needs (an endpoint, or another member the specification requires)
        # or naming an endpoint that is not https (`secure_address?`) is
        # `missing_endpoint`, since it names no endpoint sign-in can use; one
        # whose members are of the wrong shape (an endpoint that is no URL)
        # is `not_json`, a document that is JSON but not a discovery
        # document.
        #
        # The issuer is compared here as well as by the gem: the gem's check
        # runs only while the process-wide `OpenIDConnect.validate_discovery_issuer`
        # is true, and anything may set it false.
        def discovered(document)
          response = OpenIDConnect::Discovery::Provider::Config::Response.new(document.deep_symbolize_keys)
          response.expected_issuer = issuer
          # Exact: a blank or absent issuer is no match either.
          raise Unavailable.new("a document naming another issuer", reason: "issuer_mismatch") if response.issuer != issuer
          response.validate!
          raise Unavailable.new("a document with no token endpoint", reason: "missing_endpoint") if response.token_endpoint.blank?

          endpoints = [ response.authorization_endpoint, response.token_endpoint, response.jwks_uri ]
          unless endpoints.all? { |endpoint| self.class.secure_address?(parsed_address(endpoint)) }
            raise Unavailable.new("a document naming an endpoint that is not https", reason: "missing_endpoint")
          end

          Configuration.new(
            issuer: response.issuer, authorization_endpoint: response.authorization_endpoint,
            token_endpoint: response.token_endpoint, jwks_uri: response.jwks_uri,
            scopes_supported: words(response.scopes_supported),
            token_auth_methods: words(response.token_endpoint_auth_methods_supported).presence || DEFAULT_TOKEN_AUTH
          ).to_h.stringify_keys
        rescue OpenIDConnect::ValidationFailed
          missing = response.errors.details.values.flatten.any? { |detail| detail[:error] == :blank }
          raise Unavailable.new("a document missing a member", reason: "missing_endpoint") if missing

          raise Unavailable.new("a document of the wrong shape", reason: "not_json")
        end

        # `text` parsed when it is a JSON object, else nil.
        def json_object(text)
          value = JSON.parse(text.to_s)
          value if value.is_a?(Hash)
        rescue JSON::ParserError
          nil
        end

        def parsed_address(value)
          URI.parse(value.to_s)
        rescue URI::InvalidURIError
          nil
        end

        # The set's signing keys, each cut to the members a signature check
        # reads. A key of another type, or with a member of another shape
        # (a `kty` or `n` that is no string), is left out rather than handed
        # to json-jwt, which would raise a `NoMethodError` building it, so a
        # set the provider got wrong refuses its tokens (no key by that `kid`)
        # and never raises. A key with no `kid` is left out too: an ID token
        # is checked only against the key its `kid` names
        # (`SignIn::Oidc::IdToken`).
        def key_set(document)
          keys = document["keys"]
          raise Unavailable.new("a key set with no keys", reason: "not_json") unless keys.is_a?(Array) && keys.all?(Hash)

          { "keys" => keys.select { |key| usable_key?(key) }.map { |key| key.slice(*KEY_MEMBERS.fetch(key["kty"]), *KEY_LABELS).compact } }
        end

        def usable_key?(key)
          members = KEY_MEMBERS[key["kty"]]
          members && (members + [ "kid" ]).all? { |name| key[name].is_a?(String) } &&
            (KEY_LABELS - [ "kid" ]).all? { |name| key[name].nil? || key[name].is_a?(String) }
        end

        def words(value) = Array(value).grep(String)

        def uri
          URI.parse(issuer)
        rescue URI::InvalidURIError
          nil
        end
    end
  end
end
