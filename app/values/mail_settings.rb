require "openssl"

# The one reader of outgoing mail's settings and state (docs/reference/mail.md,
# spec docs/superpowers/specs/2026-10-28-mail-design.md): what the effective
# settings are, where each came from, whether they are complete, whether a
# send has shown they work, and the options a send is made with. Nothing else
# in `app/` or `lib/` reads a `MAIL_*` variable or a `mail_` column for
# delivery.
#
# EACH FIELD COMES FROM THE HOST OR FROM THE SITE. A host variable that is set
# and not blank wins for that field alone (`source(field)` says which); a
# variable that is set but empty counts as not set (a deploy file with
# `MAIL_SMTP_PASSWORD=` must not blank the screen's value and lock the field).
# A value is never logged, printed or rendered by this class: `login_set?`
# answers a boolean, and no method here puts the username or the password into
# a string that leaves the object, but `smtp_options` (handed to Action Mailer).
#
# SECURITY. `starttls` (REQUIRED -- never "if offered", which someone on the
# network can strip) or `tls`. `none` exists for a host's own relay, comes only
# from `MAIL_SMTP_SECURITY=none` and only without a login (a login sent in the
# clear is refused by never being complete); the `mail_security` column never
# accepts it. Unset, security is `starttls`. A host value that is none of the
# three is not guessed at: the settings are incomplete.
#
# THE STAND-IN. Outside production the delivery method Rails is configured
# with (`:test` in test, `:file` into tmp/mails in development) stands in for
# a server when none is set (plan Ruling 1), so "Send test mail" turns resets
# and invites on in development without a provider. `stand_in:` is a keyword
# so a test can pass nil and ask the production rules without `Rails.env`.
#
# THE STATE is one of four, derived on every read:
#   :not_set_up  the effective settings are incomplete, or production has no
#                site address (no link could be mailed)
#   :untested    complete, and nothing verified for THESE settings
#   :working     verified, and no failure since
#   :failed      verified, and a failure later than the last success
# "Verified" is `mail_verified_at` with `mail_verified_fingerprint` equal to
# the fingerprint of the effective delivery settings now: a change in the
# Settings screen or a changed host variable at a deploy makes a verified site
# untested again, with no write. The sender NAME is not a delivery setting.
#
# THE FINGERPRINT is an HMAC-SHA256 over the six delivery settings (server,
# port, security, username, password, sender address) keyed by a key derived
# from the application's secret: one-way, so the stored value says nothing of
# the password without that secret. Never shown, logged or audited.
#
# THE STATE IS WRITTEN with `update_columns` and `# version: none`, never by a
# save of `SiteSetting`: any save bumps the public content version
# (`SiteSetting#reset_cached_state`) and a mail must not empty the site's
# caches. Neither writer locks anything: a lost update costs one timestamp.
class MailSettings
  FIELDS = %i[server port security username password sender_name sender_address].freeze
  DELIVERY_FIELDS = (FIELDS - %i[sender_name]).freeze

  ENV_NAMES = {
    server: "MAIL_SMTP_SERVER", port: "MAIL_SMTP_PORT", security: "MAIL_SMTP_SECURITY",
    username: "MAIL_SMTP_USERNAME", password: "MAIL_SMTP_PASSWORD",
    sender_name: "MAIL_SENDER_NAME", sender_address: "MAIL_SENDER_ADDRESS"
  }.freeze

  STORED_SECURITY = %w[starttls tls].freeze
  HOST_SECURITY = (STORED_SECURITY + %w[none]).freeze
  DEFAULT_SECURITY = "starttls".freeze
  STATES = %i[not_set_up untested working failed].freeze

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  FINGERPRINT_KEY = "content_spiel mail fingerprint".freeze

  def self.current(site = Current.site, env: ENV, production: Rails.env.production?, address: SiteAddress.current,
    stand_in: (production ? nil : ActionMailer::Base.delivery_method))
    new(site, env: env, production: production, address: address, stand_in: stand_in)
  end

  # A send succeeded. Always records the send; marks the settings VERIFIED only
  # when `fingerprint` is the current one: a mail queued under settings that
  # have since changed proves nothing about the new ones.
  def self.record_success!(fingerprint:, at: Time.current)
    site = Current.site
    columns = { mail_last_sent_at: at }
    if fingerprint.present? && ActiveSupport::SecurityUtils.secure_compare(fingerprint.to_s, current(site).fingerprint)
      columns.merge!(mail_verified_at: at, mail_verified_fingerprint: fingerprint)
    end
    site.update_columns(columns) # version: none (mail's state is not content)
  end

  # A real send failed after its last attempt. `key` is the sentence's key
  # (login, connect, security, sender, other) and `line` the server's reply
  # with the login already scrubbed out by the caller.
  def self.record_failure!(key:, line:, at: Time.current)
    Current.site.update_columns(mail_failed_at: at, mail_failure: { "key" => key.to_s, "line" => line.to_s }) # version: none (mail's state is not content)
  end

  attr_reader :site

  def initialize(site, env:, production:, address:, stand_in:)
    @site = site
    @env = env
    @production = production
    @address = address
    @stand_in = stand_in
  end

  # The effective value of a field: the host's when its variable is set, else
  # the site's, else nil (security: the default). Port is an Integer or nil.
  def value(field)
    field = field.to_sym
    raise ArgumentError, "unknown mail field #{field.inspect}" unless FIELDS.include?(field)

    memo[field] = compute(field) unless memo.key?(field)
    memo[field]
  end

  # :host, :site or :none.
  def source(field)
    return :host if host_value(field.to_sym)

    stored?(field.to_sym) ? :site : :none
  end

  def from_host?(field) = source(field) == :host

  def all_from_host? = FIELDS.all? { |field| from_host?(field) }

  # Whether a username or a password is in effect, without showing either.
  # The site's login is read off the raw columns (`SiteSetting#mail_login_set?`).
  def login_set?
    host_value(:username).present? || host_value(:password).present? || site.mail_login_set?
  end

  def stand_in? = @stand_in.present? && value(:server).blank?

  # Server, port and sender address are present (a stand-in needs no server),
  # the security is one we know and, for `none`, there is no login, and in
  # production the site has an address to build links from.
  def complete?
    return false if @production && !@address&.configured?
    return false if value(:sender_address).blank?
    return false unless security_acceptable?

    stand_in? || (value(:server).present? && value(:port).present?)
  end

  def fingerprint
    key = Rails.application.key_generator.generate_key(FINGERPRINT_KEY, 32)
    OpenSSL::HMAC.hexdigest("SHA256", key, DELIVERY_FIELDS.map { |field| value(field) }.to_json)
  end

  def state
    return :not_set_up unless complete?
    return :untested unless verified?

    failed_since_verified? ? :failed : :working
  end

  # What shows the reset link and the invites.
  def ready? = %i[working failed].include?(state)

  # When the last verified send happened and the last failure, for the card
  # and the System status row ("Last mail sent 14 Oct, 09:12.").
  def last_sent_at = site.mail_last_sent_at
  def failed_at = site.mail_failed_at
  def failure = site.mail_failure

  # "Name <address>", quoted by the mail gem; the address alone with no name.
  def sender
    address = Mail::Address.new(value(:sender_address).to_s)
    address.display_name = value(:sender_name) if value(:sender_name).present?
    address.format
  end

  # For the SMTP delivery of a message (`ApplicationMailer`). Port and
  # server are the effective ones; the login only when there is one.
  #
  # Each security says all three of the mail gem's switches, because the gem
  # fills in what is not said: with neither STARTTLS switch given it uses
  # STARTTLS "if offered" (`:auto`), so `none` would become STARTTLS whenever
  # a server offered it (or plain whenever someone on the way struck the
  # offer). `starttls` is `:always` (net-smtp refuses a server that does not
  # offer it, before the login), `tls` is TLS from the first byte with both
  # STARTTLS switches off (the gem refuses `tls` beside either), and `none`
  # is plain SMTP with both off: never upgraded, as the host asked.
  def smtp_options
    options = { address: value(:server), port: value(:port) }
    if login_set?
      options[:user_name] = value(:username)
      options[:password] = value(:password)
      options[:authentication] = :plain
    end
    options.merge!(
      case value(:security)
      when "starttls" then { enable_starttls: true, enable_starttls_auto: false }
      when "tls" then { tls: true, enable_starttls: false, enable_starttls_auto: false }
      else { enable_starttls: false, enable_starttls_auto: false }
      end
    )
    options.merge(open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
  end

  private

  def memo = (@memo ||= {})

  # A host variable's text, nil for unset or blank.
  def host_value(field)
    @env[ENV_NAMES.fetch(field)].to_s.strip.presence
  end

  def stored?(field)
    case field
    when :username, :password then site.public_send(:"mail_#{field}_before_type_cast").present?
    else site.public_send(:"mail_#{field}").present?
    end
  end

  def compute(field)
    host = host_value(field)
    case field
    when :port then host ? Integer(host, 10, exception: false)&.then { |port| port if (1..65_535).cover?(port) } : site.mail_port
    when :security then security(host)
    when :username, :password then host || stored_secret(field)
    else host || site.public_send(:"mail_#{field}")
    end
  end

  # A host value outside the three is returned as it is, so
  # `security_acceptable?` can refuse it; the column's `none` (or anything
  # else) is not accepted and reads as the default.
  def security(host)
    return host if host
    return site.mail_security if STORED_SECURITY.include?(site.mail_security)

    DEFAULT_SECURITY
  end

  # A login the current encryption keys can't read is "not there" for the
  # delivery (the fingerprint and a send), while `login_set?` still says
  # it is stored so the screen can offer to replace it.
  def stored_secret(field)
    site.public_send(:"mail_#{field}").presence
  rescue ActiveRecord::Encryption::Errors::Base
    nil
  end

  def security_acceptable?
    case value(:security)
    when *STORED_SECURITY then true
    when "none" then !login_set?
    else false
    end
  end

  def verified?
    site.mail_verified_at.present? && site.mail_verified_fingerprint.present? &&
      ActiveSupport::SecurityUtils.secure_compare(site.mail_verified_fingerprint, fingerprint)
  end

  def failed_since_verified?
    site.mail_failed_at.present? && site.mail_failed_at > site.mail_verified_at
  end
end
