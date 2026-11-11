# A visitor's address as a counter knows it: what is counted, and the key it
# is counted under. Every per-visitor counter of the site (a form's sends,
# sign-in's throttle) keys through here, so they cut an address alike.
#
# AN IPv6 VISITOR IS THEIR /64. One household or phone is handed a whole /64
# and may send from any address in it, so counting the full address would
# give one person 2^64 counters. An IPv4 visitor is the full address (a /24
# would hold many households behind one provider), an IPv4-mapped IPv6 one
# is its IPv4 address, and a value that does not parse is counted as written.
#
# THE STORE HOLDS NO ADDRESS: `key` is a hex HMAC-SHA256 of the normalised
# address, its secret derived from `secret_key_base` per purpose through
# `Rails.application.key_generator`, so Solid Cache (a table of the
# database) holds no IP, and two counters that name two purposes never share
# a key for one visitor.
#
# The address is `request.remote_ip`, which is right only behind proxies
# Rails trusts (`docs/reference/hosting.md`): behind a CDN it does not trust,
# every visitor is the CDN's edge and shares one key.
module VisitorAddress
  # What is counted: "203.0.113.7", "2001:db8:1:2::/64", or the value as
  # written.
  def self.normalise(ip)
    address = IPAddr.new(ip.to_s)
    address.ipv6? && !address.ipv4_mapped? ? "#{address.mask(64)}/64" : address.native.to_s
  rescue IPAddr::Error
    ip.to_s
  end

  # 64 hex characters.
  def self.key(ip, purpose:) = digest(normalise(ip), purpose: purpose)

  # The same HMAC of a text as written, for a counter that keys something
  # beside the address under the same purpose (sign-in's account, an email
  # the caller normalised): an email is not cut as an address would be.
  def self.digest(text, purpose:)
    OpenSSL::HMAC.hexdigest("SHA256", secret(purpose), text.to_s)
  end

  # The application's key generator caches each purpose's key, so the PBKDF2
  # run behind it is made once per process, not per request.
  def self.secret(purpose)
    Rails.application.key_generator.generate_key(purpose)
  end
  private_class_method :secret
end
