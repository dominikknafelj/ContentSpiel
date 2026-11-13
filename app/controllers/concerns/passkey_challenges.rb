# The challenge a WebAuthn ceremony is answered to, kept between the options
# a browser is handed and the answer it sends back.
#
# KEPT IN A COOKIE OF ITS OWN PER PURPOSE, never in the Rails session:
# `cs_passkey_<purpose>`, encrypted, httponly, SameSite=Strict, path "/",
# holding `{ "purpose", "challenge", "at" }`. It is a browser-session cookie
# with no `Expires`: the lifetime is the server's check of `at`, and a date
# of the browser's own would only drop the cookie early on a machine whose
# clock runs ahead of the server's.
# Only the options answer (`#issue_passkey_challenge`) writes it and only the
# take (`#take_passkey_challenge`) deletes it. The session would not do: the
# cookie store writes the whole session back on every request that loads it,
# changed or not, so any request sent with the cookie from before the
# options (a favicon, a prefetch, a live refresh) would answer after them
# and put the session back without the challenge. A cookie jar writes only
# the cookies a request assigned, so no other request touches these.
#
# One older than LIFETIME, or issued for another purpose (a registration's
# sent to sign-in), is no challenge, and the answer is refused as a wrong
# passkey. So a script that holds options keeps them from lapsing
# (`passkeys/held_options`): it fetches fresh ones before LIFETIME is up and
# when its tab is shown again, which also gives the visible tab the cookie
# when a second tab has written its own.
#
# TAKEN ONCE, ON THE SERVER. The challenge's cookie is the browser's, so
# deleting it only tells the browser to drop its copy: whoever kept the
# cookie could send it again with a captured assertion,
# and a synced passkey's counter (always 0) would not stop it. So taking a
# challenge also spends it in `SignIn::SpentChallenge`, a table with a
# unique digest, in one atomic insert that does nothing on a duplicate: of
# any number of sends of one challenge, even at the same moment, exactly
# one inserts the row and is let through. A failed statement or a lost
# connection is no spend, so the challenge is refused and the error's class
# logged; any other error is the code's own and is raised. The row lives a second past the challenge's
# own lifetime, so it never lapses before the challenge does, and sits in
# a table so that no cache eviction can drop it. The digest is an HMAC of
# the purpose and the challenge, never the challenge itself. Every purpose
# is taken this way, and a challenge is spent whatever its answer turns out
# to be.
#
# The challenge reaches no page, span or log line: it is only in its
# encrypted cookie, which no script can read, and the table holds only its
# HMAC.
module PasskeyChallenges
  extend ActiveSupport::Concern

  LIFETIME = 5.minutes
  PURPOSES = %w[sign_in second_factor confirm register].freeze
  COOKIE_PREFIX = "cs_passkey_".freeze

  # The cookie of every purpose, which a sign-out deletes
  # (`Authentication#terminate_session`).
  def self.cookie_names = PURPOSES.map { |purpose| "#{COOKIE_PREFIX}#{purpose}" }

  private

  def issue_passkey_challenge(purpose, challenge)
    raise ArgumentError, "#{purpose.inspect} is not among #{PURPOSES}" unless PURPOSES.include?(purpose)

    now = Time.current
    cookies.encrypted[passkey_challenge_cookie(purpose)] = {
      value: { "purpose" => purpose, "challenge" => challenge, "at" => now.to_i },
      httponly: true, same_site: :strict, secure: request.ssl?, path: "/"
    }
    nil
  end

  def take_passkey_challenge(purpose)
    raise ArgumentError, "#{purpose.inspect} is not among #{PURPOSES}" unless PURPOSES.include?(purpose)

    name = passkey_challenge_cookie(purpose)
    kept = cookies.encrypted[name]
    cookies.delete(name, path: "/")
    return nil unless kept.is_a?(Hash) && kept["purpose"] == purpose && kept["challenge"].is_a?(String)
    return nil unless kept["at"].is_a?(Integer)

    expires_at = Time.zone.at(kept["at"] + LIFETIME.to_i)
    return nil unless expires_at >= Time.current && spend_passkey_challenge(purpose, kept["challenge"], expires_at)

    kept["challenge"]
  end

  def passkey_challenge_cookie(purpose) = "#{COOKIE_PREFIX}#{purpose}"

  # True for the one take that inserted the challenge's digest.
  def spend_passkey_challenge(purpose, challenge, expires_at)
    SignIn::SpentChallenge.take(purpose: purpose, value: challenge, expires_at: expires_at + 1.second)
  end

  # The relying party this request's passkeys belong to (`SignIn::RelyingParty`),
  # or nil at an IP address, where no passkey is offered. Named after the
  # site, or its host while it has no title.
  def passkey_relying_party
    return @passkey_relying_party if defined?(@passkey_relying_party)

    name = ::Locales.read(Current.site, :title, locale: ::Locales.default).presence || request.host
    @passkey_relying_party = SignIn::RelyingParty.for(request_origin: request.base_url, name: name)
  end
end
