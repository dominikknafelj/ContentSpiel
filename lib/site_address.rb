require "uri"

# The site's public address, parsed once from `PUBLIC_HOST` (else
# `SITEMAP_HOST`, its older name). Everything that must agree about "where
# this site lives" (host authorisation, HTTPS, absolute URLs, head tags)
# reads it here instead of splitting the variable itself.
#
# `lib/` is not autoloaded in this app: `config/application.rb` requires
# this file, and it uses nothing of Rails.
#
# A blank value is "not configured" (a local checkout has none), never an
# error; a value that is there but is not an absolute http(s) address with a
# host raises `Invalid` at once, so a typo stops the boot instead of quietly
# producing wrong links.
#
# THE MESSAGE NEVER REPEATS THE VALUE. It goes to the boot log, and a value
# someone typed as `https://user:password@…` would put the password there.
# It names the variable the value came from instead, which is what the
# person has to go and look at.
class SiteAddress
  class Invalid < ArgumentError; end

  DEFAULT_PORTS = { "http" => 80, "https" => 443 }.freeze
  PORTS = (1..65_535)

  # Read in this order; a blank one counts as not there.
  VARIABLES = %w[PUBLIC_HOST SITEMAP_HOST].freeze

  attr_reader :host, :port

  # `source` is the name of the variable the value came from, for the
  # message only.
  #
  # What is refused, beside a value with no scheme or no host: user info (an
  # origin has none, and dropping it silently would leave a password sitting
  # in the environment unnoticed), a port outside 1..65535, any whitespace or
  # control character inside the value (a newline would also break the log
  # line), and a host that is not ASCII (write it in its xn-- form; nothing
  # is converted here). What is normalised: the scheme and the host are
  # lower-cased, a trailing dot of the host is dropped (no request's Host
  # would match it), the scheme's default port is dropped, and an IPv6
  # literal keeps its brackets, as `config.hosts` and `url_for` want it.
  def self.parse(value, source: VARIABLES.first)
    text = value.to_s.strip
    return new(nil, nil, nil) if text.empty?
    raise invalid(source) if text.match?(/[[:space:][:cntrl:]]/) || !text.ascii_only?

    uri = begin
      URI.parse(text)
    rescue URI::InvalidURIError
      raise invalid(source)
    end
    scheme = uri.scheme.to_s.downcase
    host = uri.host.to_s.downcase.chomp(".")
    # An "@" in the authority is user info even when it is empty
    # (`https://@host`), which URI reports as none.
    user_info = uri.userinfo || text[%r{\A[^:/?#]+://([^/?#]*)}, 1].to_s.include?("@")
    raise invalid(source) unless DEFAULT_PORTS.key?(scheme) && !host.empty? && !user_info && PORTS.cover?(uri.port)

    new(scheme, host, uri.port == DEFAULT_PORTS[scheme] ? nil : uri.port)
  end

  # Memoised: the environment does not change while the app runs. Tests that
  # set `ENV` go through `with_site_address` (test/support/site_address_helper.rb),
  # which calls `reset!` before and after.
  def self.current
    @current ||= begin
      source = VARIABLES.find { |name| !ENV[name].to_s.strip.empty? }
      parse(source && ENV[source], source: source || VARIABLES.first)
    end
  end

  def self.reset!
    @current = nil
  end

  def self.invalid(source)
    Invalid.new("#{source} must be the site's address with its scheme, for example https://www.example.org")
  end
  private_class_method :invalid

  def initialize(scheme, host, port)
    @scheme = scheme
    @host = host
    @port = port
    freeze
  end

  def configured? = !@host.nil?

  def https? = @scheme == "https"

  # "https://docs.example.org" or "http://localhost:3030"; no path, no
  # trailing slash, no default port. nil when not configured.
  def origin
    return nil unless configured?

    "#{@scheme}://#{@host}#{":#{@port}" if @port}"
  end

  # Options for Rails' `url_for` / `default_url_options`; {} when not configured.
  def url_options
    return {} unless configured?

    { host: @host, protocol: @scheme, port: @port }.compact
  end
end
