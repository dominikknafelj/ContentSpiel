require_relative "site_address"

# What a host decides about the site's address, turned into Rails
# configuration in one place: which host names are answered, whether HTTPS is
# forced, the address in mailed links, and what the boot says about it.
# `config/environments/production.rb` calls `apply` and sets none of these
# itself; development and test never call it, so they answer any host.
#
# Required by `config/application.rb` beside `site_address`, although `lib/`
# is autoloaded: the environment file runs before any autoloading is set up.
# For the same reason nothing here leans on Active Support (no `1.year`, no
# `present?`), and nothing names a class of Rails.
module HostSettings
  class MissingSecret < StandardError; end

  # The proxy's health check asks `/up` by IP and over plain HTTP, so it is
  # left out of both host authorisation and the HTTPS redirect. The path
  # exactly: `/up/x` is an ordinary request.
  HEALTH_CHECK = ->(request) { request.path == "/up" }

  # HSTS as the design says it, written out and not left to Rails' default
  # (two years, subdomains included): one year, for this host name alone, no
  # preload. `includeSubDomains` would force HTTPS, in every visitor's
  # browser and for as long as the header says, on whatever else the host
  # runs under the same name (mail, an old intranet on plain HTTP), and a
  # server cannot take that back once a browser has seen it.
  ONE_YEAR = 365 * 24 * 60 * 60
  HSTS = { expires: ONE_YEAR, subdomains: false, preload: false }.freeze

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
    config.ssl_options = { redirect: { exclude: HEALTH_CHECK }, hsts: HSTS }

    # Only for a proxy that ends TLS and does not send X-Forwarded-Proto
    # (Kamal's proxy sends it, and Thruster passes it on). "1" and nothing
    # else: a value such as "true" or "0" must not quietly mean yes.
    config.assume_ssl = assume_ssl?(env)

    config.action_mailer.default_url_options = address.url_options
  end

  def self.assume_ssl?(env) = env["ASSUME_SSL"] == "1"
  private_class_method :assume_ssl?

  # The boot log lines, one fact each: a wrong PUBLIC_HOST refuses every
  # request with a 403 that says nothing, so this is where a person reads
  # which address is answered. The second line is there because the match is
  # exact and that is the surprise: an address of `example.org` refuses
  # `www.example.org`. The last says when the proxy's word about HTTPS is
  # not asked for.
  def self.announcement(address, env = ENV)
    lines = []
    if !address.configured?
      lines << "[ContentSpiel] PUBLIC_HOST is not set. Any host name is accepted and nothing is forced to HTTPS."
    else
      lines << if address.https?
        "[ContentSpiel] Serving #{address.origin}. Other host names are refused; plain HTTP is redirected."
      else
        "[ContentSpiel] Serving #{address.origin}. Other host names are refused. The connection is not encrypted."
      end
      lines << "[ContentSpiel] Only the exact host name #{address.host} is answered: " \
               "not www.#{address.host}, not any other subdomain."
    end
    lines << "[ContentSpiel] ASSUME_SSL=1: every request is taken as HTTPS, whatever the proxy says." if assume_ssl?(env)
    lines
  end

  HOW_TO_SET = "Make a value with `bin/rails secret` and set it as the environment variable SECRET_KEY_BASE; " \
               "keep it the same across restarts."

  # Rails' own error for a missing secret sends the reader to
  # `bin/rails credentials:edit`, which a container has no key for. This one
  # names the variable and how to make a value, and never holds a value.
  #
  # It decides as Rails does (`ENV["SECRET_KEY_BASE"] || credentials`), in
  # that order:
  # - the variable holds a secret: accepted, and the credentials are NOT
  #   read, as Rails does not read them then, so a broken credentials file
  #   cannot stop a boot that needs nothing from it;
  # - the variable is set but blank (a compose file's
  #   `SECRET_KEY_BASE=${SECRET_KEY_BASE}` with nothing behind it): refused,
  #   also when the credentials hold a secret, because Rails takes the blank
  #   value for the secret and fails on it with its own message;
  # - the variable is not set: the credentials' `secret_key_base` decides.
  #
  # `credentials` is anything that answers `secret_key_base`, in production
  # `Rails.application.credentials`, which decrypts only when asked. Asking
  # can raise (a master key that does not open the file, a key of the wrong
  # length, a file that is not YAML, a file that cannot be opened); whatever
  # is raised is "could not be read" and the message names the error's
  # class, never its text, with no cause attached. Rescuing every
  # StandardError is what keeps this file free of Rails' error classes, and
  # it fails closed: the outcome of the rescue is always a refusal.
  def self.require_secret!(env, credentials: nil)
    from_env = env["SECRET_KEY_BASE"]
    return if secret?(from_env)

    unless from_env.nil?
      raise MissingSecret, "SECRET_KEY_BASE is set but empty. ContentSpiel signs sessions and tokens with it and " \
                           "does not start in production without one. #{HOW_TO_SET}"
    end

    unreadable = nil
    found = begin
      secret?(credentials&.secret_key_base)
    rescue StandardError => error
      unreadable = error.class.name
      false
    end
    return if found

    message = "SECRET_KEY_BASE is not set. ContentSpiel signs sessions and tokens with it and " \
              "does not start in production without one. #{HOW_TO_SET}"
    if unreadable
      message += " A credentials file exists but could not be read (#{unreadable}): if the secret is meant to " \
                 "come from it, check RAILS_MASTER_KEY."
    end
    raise MissingSecret, message
  end

  def self.secret?(value) = value.is_a?(String) && !value.strip.empty?
  private_class_method :secret?
end
