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
class SiteAddress
  class Invalid < ArgumentError; end

  DEFAULT_PORTS = { "http" => 80, "https" => 443 }.freeze

  attr_reader :host, :port

  def self.parse(value)
    text = value.to_s.strip
    return new(nil, nil, nil) if text.empty?

    uri = begin
      URI.parse(text)
    rescue URI::InvalidURIError
      raise invalid(text)
    end
    raise invalid(text) unless %w[http https].include?(uri.scheme) && !uri.host.to_s.empty?

    port = uri.port == DEFAULT_PORTS[uri.scheme] ? nil : uri.port
    new(uri.scheme, uri.host.downcase, port)
  end

  # Memoised: the environment does not change while the app runs. Tests that
  # set `ENV` call `reset!` before and after.
  def self.current
    @current ||= parse(presence(ENV["PUBLIC_HOST"]) || presence(ENV["SITEMAP_HOST"]))
  end

  def self.reset!
    @current = nil
  end

  def self.invalid(text)
    Invalid.new(%(PUBLIC_HOST must be the site's address with its scheme, for example https://www.example.org (got: "#{text}")))
  end
  private_class_method :invalid

  def self.presence(value)
    value.to_s.strip.empty? ? nil : value
  end
  private_class_method :presence

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
