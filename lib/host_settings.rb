require_relative "site_address"

# What a host decides about the site's address, turned into Rails
# configuration in one place: which host names are answered, whether HTTPS is
# forced, the address in mailed links, and what the boot says about it.
# `config/environments/production.rb` calls `apply` and sets none of these
# itself; development and test never call it, so they answer any host.
#
# Required by `config/application.rb` beside `site_address`: the environment
# file runs before anything is autoloaded.
module HostSettings
  class MissingSecret < StandardError; end

  # The proxy's health check asks `/up` by IP and over plain HTTP, so it is
  # left out of both host authorisation and the HTTPS redirect. The path
  # exactly: `/up/x` is an ordinary request.
  HEALTH_CHECK = ->(request) { request.path == "/up" }

  # `address` and `env` are parameters so a test hands in its own; production
  # takes the defaults. `SiteAddress.current` raises `SiteAddress::Invalid`
  # for a value that is not an address, which stops the boot in the
  # environment file with a message that names the variable.
  def self.apply(config, address: SiteAddress.current, env: ENV)
    # Without an address `config.hosts` is left as it is (empty in
    # production: any host is answered), never emptied, so whatever else
    # filled it keeps its entries.
    config.hosts = [ address.host ] if address.configured?
    config.host_authorization = { exclude: HEALTH_CHECK }

    # HTTPS follows the address's own scheme: an http address (a private
    # network, a trial on localhost) is served as it is, with no redirect, no
    # HSTS and no Secure cookie, and the boot line says so.
    config.force_ssl = address.https?
    config.ssl_options = { redirect: { exclude: HEALTH_CHECK } }

    # Only for a proxy that ends TLS and does not send X-Forwarded-Proto
    # (Kamal's proxy and Thruster send it). "1" and nothing else: a value
    # such as "true" or "0" must not quietly mean yes.
    config.assume_ssl = env["ASSUME_SSL"] == "1"

    config.action_mailer.default_url_options = address.url_options
  end

  # The boot log line: a wrong PUBLIC_HOST refuses every request with a 403
  # that says nothing, so this is where a person reads which address is
  # answered.
  def self.announcement(address)
    if !address.configured?
      "[ContentSpiel] PUBLIC_HOST is not set. Any host name is accepted and nothing is forced to HTTPS."
    elsif address.https?
      "[ContentSpiel] Serving #{address.origin}. Other host names are refused; plain HTTP is redirected."
    else
      "[ContentSpiel] Serving #{address.origin}. Other host names are refused. The connection is not encrypted."
    end
  end

  # Rails' own error for a missing secret sends the reader to
  # `bin/rails credentials:edit`, which a container has no key for. This one
  # names the variable and how to make a value. It is no stricter than Rails:
  # a secret in the encrypted credentials file (read with RAILS_MASTER_KEY)
  # is accepted as Rails accepts it, so `credentials` is anything that
  # answers `secret_key_base`, or nil when there is none or it cannot be
  # read; the caller decides what "cannot be read" is. The value itself is
  # never read into a message.
  def self.require_secret!(env, credentials: nil)
    return if present?(env["SECRET_KEY_BASE"]) || present?(credentials&.secret_key_base)

    raise MissingSecret, "SECRET_KEY_BASE is not set. ContentSpiel signs sessions and tokens with it and " \
                         "does not start in production without one. Make a value with `bin/rails secret` and " \
                         "set it as the environment variable SECRET_KEY_BASE; keep it the same across restarts. " \
                         "(A secret_key_base in the encrypted file that RAILS_MASTER_KEY opens is accepted too; " \
                         "none could be read.)"
  end

  def self.present?(value) = !value.to_s.strip.empty?
  private_class_method :present?
end
