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
    # This class is the only reader of the five variables.
    class Provider
      LOOPBACK = %w[127.0.0.1 [::1] localhost].freeze

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

      def check_issuer!(production:)
        parsed = uri
        usable = parsed&.host.present? && parsed.userinfo.nil? && (parsed.scheme == "https" || (parsed.scheme == "http" && !production && LOOPBACK.include?(parsed.host)))
        raise Misconfigured, "SSO_ISSUER must be an absolute https URL with a host (http only to localhost, outside production)." unless usable
      end

      private
        def client_secret = @secret

        def uri
          URI.parse(issuer)
        rescue URI::InvalidURIError
          nil
        end
    end
  end
end
