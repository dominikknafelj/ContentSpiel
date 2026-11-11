require "ipaddr"
require "public_suffix"

module SignIn
  # The one place that decides which site a passkey belongs to. A browser
  # binds a credential to the relying party's id for good, so a change of
  # what this answers orphans every passkey already made: an id is a
  # registrable domain (or a host), never a path, and is decided here alone.
  #
  # - With an address (`PUBLIC_HOST`), the id is the registrable domain of
  #   its host (`PublicSuffix.domain` over the full list, its private
  #   section included, so `foo.github.io` stays itself), or the host itself
  #   when it has none (`localhost`, a single label). The one allowed origin
  #   is the address: a request that reached another host is refused by
  #   host authorisation before it gets here, and a credential made there
  #   would not verify.
  # - With none (development and test), the id is the request's host and the
  #   origin the request's.
  # - At an IP address there is no relying party: WebAuthn refuses an IP as
  #   an id, so `nil` tells the caller to offer no passkey at all.
  module RelyingParty
    def self.for(address: SiteAddress.current, request_origin:, name:)
      if address.configured?
        host = address.host
        origin = address.origin
        id = PublicSuffix.domain(host) || host
      else
        origin = request_origin.to_s
        host = host_of(origin)
        id = host
      end
      return nil if host.blank? || ip?(host)

      WebAuthn::RelyingParty.new(id: id, name: name, allowed_origins: [ origin ])
    end

    def self.host_of(origin)
      URI.parse(origin).host&.downcase
    rescue URI::InvalidURIError
      nil
    end

    def self.ip?(host)
      IPAddr.new(host.delete_prefix("[").delete_suffix("]"))
      true
    rescue IPAddr::Error
      false
    end
    private_class_method :host_of, :ip?
  end
end
