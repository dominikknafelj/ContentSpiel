require "ipaddr"

# Which proxies in front of the site are believed when they say whose request
# it is, from one variable, TRUSTED_PROXIES: a comma-separated list of
# address ranges (`173.245.48.0/20, 2400:cb00::/32`), a bare address being a
# range of one. They are ADDED to Rails' own list (`ActionDispatch::RemoteIp::
# TRUSTED_PROXIES`: loopback and the private ranges, so kamal-proxy on the
# same host needs nothing), never put in its place: a list that replaced it
# would make the proxy on the host itself the visitor of every request.
#
# Why it matters: every per-address count keys on `request.remote_ip` (the
# sign-in's buckets, the bot check's trigger, the forms' send limit). Behind
# a CDN whose addresses Rails does not trust, that is the CDN's edge, and
# every visitor is one of a few addresses: fifty failures from anyone close
# sign-in for everyone. System status's "Visitor address" row says when
# Cloudflare's header shows it (`Setup::SystemCheck#visitor_address`).
#
# Required by `config/application.rb`, although `lib/` is autoloaded:
# `config/environments/production.rb` calls `apply` while the application is
# being configured, before any autoloading is set up, and the file is not
# reloaded (a change needs a restart in development). Unset or blank, the
# variable changes nothing: Rails' default stands.
module TrustedProxies
  class Invalid < StandardError; end

  # The ranges the variable names, as `IPAddr`s, in its order; empty when it
  # is unset or blank. An entry that is not an address or a range stops the
  # boot with a message that names the variable and the entry (an empty one
  # between two commas included, since `a,,b` is a typo, not a choice). A
  # range is what `IPAddr` reads, so `10.0.0.1/8` is the range 10.0.0.0/8.
  def self.parse(value)
    text = value.to_s.strip
    return [] if text.empty?

    text.split(",", -1).map do |entry|
      entry = entry.strip
      begin
        raise IPAddr::InvalidAddressError if entry.empty?
        IPAddr.new(entry)
      rescue IPAddr::Error
        raise Invalid, "TRUSTED_PROXIES holds “#{entry}”, which is not an address or an address range " \
                       "(such as 173.245.48.0/20 or 2400:cb00::/32). Separate entries with commas."
      end
    end
  end

  # Rails' list with the variable's ranges after it, or nil when the variable
  # names none (Rails' middleware then takes its own default).
  def self.list(env = ENV)
    extra = parse(env["TRUSTED_PROXIES"])
    return nil if extra.empty?

    ActionDispatch::RemoteIp::TRUSTED_PROXIES + extra
  end

  def self.apply(config, env: ENV)
    proxies = list(env)
    config.action_dispatch.trusted_proxies = proxies if proxies
  end
end
