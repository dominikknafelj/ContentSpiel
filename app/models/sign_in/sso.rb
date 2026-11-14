require "net/http"

module SignIn
  # Single sign-on through one OpenID Connect provider per site.
  #
  # THREE INVARIANTS hold for everything under this module. There is NO RACK
  # MIDDLEWARE: the routes are the app's own, under `/<ADMIN_PATH>/sign-in/sso/`,
  # inside the backend's host constraint, so with `ADMIN_HOST` set nothing of
  # it answers on the public host. EVERY CALL TO THE PROVIDER (discovery, keys,
  # the token endpoint) goes through `SignIn::OutsideCall`: bounded, untraced
  # and named by class, status or fixed reason, never by message. And NOTHING
  # HERE KNOWS A USER: it speaks to the provider and answers what the provider
  # said; matching an identity to an account is a service's.
  module Sso
    VARIABLES = %w[SSO_ISSUER SSO_CLIENT_ID SSO_CLIENT_SECRET SSO_NAME].freeze
    STATE_LIFETIME = 10.minutes
    CACHE_FOR = 1.hour
    MAX_BODY = 65_536
    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 5
    # What a call to the provider may raise when the provider is out of
    # reach or answers no HTTP (`Net::OpenTimeout` and `Net::ReadTimeout`
    # are `Timeout::Error`s): `unreachable`.
    NETWORK_ERRORS = [
      Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError, Net::HTTPBadResponse
    ].freeze

    # How a sign-in that did not finish is named in a span (it is not audited:
    # no one is named, and a bot's run would bury the log).
    UNFINISHED_REASONS = %w[cancelled provider_error bad_state bad_token unavailable].freeze
    # Why a finished sign-in names no account (audited as `sso.refused`).
    ACCOUNT_REASONS = %w[no_account email_unverified owner].freeze
    # A start from an invitation whose provider signed in another verified
    # email: shown on the invitation page, never audited.
    MISMATCH_REASON = "mismatch".freeze
    # Every word `auth.sso.callback`'s `auth.sso.reason` may carry.
    SPAN_REASONS = (UNFINISHED_REASONS + ACCOUNT_REASONS + [ MISMATCH_REASON ]).freeze
    # Every word `auth.sso.discovery`'s `auth.sso.reason` may carry: why the
    # discovery document or the key set could not be used, System status's
    # words, and `http_<status>` (DISCOVERY_HTTP_REASON) for a refusing status.
    DISCOVERY_REASONS = %w[unreachable not_json issuer_mismatch missing_endpoint].freeze
    DISCOVERY_HTTP_REASON = /\Ahttp_\d{3}\z/
    # Every word `auth.sso.recheck`'s `auth.sso.reason` may carry: a refresh
    # answer that came but could not be used.
    RECHECK_REASONS = %w[not_json bad_token].freeze

    # The host's variables are wrong in a way that would silently open what
    # they meant to close, or point sign-in at the wrong place.
    class Misconfigured < StandardError; end

    # The provider could not be used; `reason` is one of the System status
    # row's words (`unreachable`, `http_<status>`, `not_json`,
    # `issuer_mismatch`, `missing_endpoint`). A body over MAX_BODY is
    # `not_json` at every endpoint: it is not read, so it is no JSON object
    # sign-in can use.
    class Unavailable < SignIn::OutsideCall::Unavailable; end

    # A span's `error.type` for an `Unavailable`: the status, or the network
    # error's class, or the reason; never a message.
    def self.error_type(error)
      return error.status.to_s if error.status
      return error.cause.class.name if error.reason == "unreachable" && error.cause

      error.reason
    end

    # Whether `word` is one of discovery's span reasons.
    def self.discovery_reason?(word) = DISCOVERY_REASONS.include?(word) || DISCOVERY_HTTP_REASON.match?(word.to_s)

    # An issuer's host, which the audit log names the provider by: an
    # identity's, or the issuer an account was linked under.
    def self.issuer_host(issuer) = URI.parse(issuer.to_s).host

    # Whether the host requires single sign-on: `SSO_REQUIRED=1` and a whole
    # provider (`Provider.required?` is the one reader of the variable).
    def self.required?(env = ENV) = Provider.required?(env)

    # The origin the provider is told to send the person back to, as
    # `url_for` options: CS Studio's own address when it has one, else the
    # site's, else (development and test) the request's, as
    # `SignIn::Passkeys::RelyingParty` decides which site a passkey belongs to.
    def self.callback_origin(request_origin:)
      address = SiteAddress.admin.configured? ? SiteAddress.admin : SiteAddress.current
      return address.url_options if address.configured?

      uri = URI.parse(request_origin.to_s)
      { host: uri.host, protocol: uri.scheme, port: uri.port == uri.default_port ? nil : uri.port }.compact
    end
  end
end
