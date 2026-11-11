# The challenge a WebAuthn ceremony is answered to, kept between the options
# a browser is handed and the answer it sends back.
#
# It is kept in the Rails session (the encrypted cookie store) under
# `:passkey_challenge`, as `{ "purpose", "challenge", "at" }`, one at a time.
# One older than LIFETIME, or issued for another purpose (a registration's
# sent to sign-in), is no challenge, and the answer is refused as a wrong
# passkey. A page left open past the lifetime needs one more press: its
# script fetches fresh options after a refusal.
#
# TAKEN ONCE, ON THE SERVER. The session is a cookie the browser holds, so
# deleting the challenge from it only rewrites the browser's copy: whoever
# kept the earlier cookie could send it again with a captured assertion,
# and a synced passkey's counter (always 0) would not stop it. So taking a
# challenge also writes a spent mark in `SignIn.store` with
# `unless_exist`, for what is left of its lifetime, and a challenge whose
# mark was already written (or whose mark could not be written) is no
# challenge. The mark is keyed by an HMAC of the purpose and the
# challenge, never the challenge itself. Every purpose is taken this way,
# and a challenge is spent whatever its answer turns out to be.
#
# The challenge reaches no page, span or log line: it is only in the cookie,
# which the browser cannot read, and the store holds only its HMAC.
module PasskeyChallenges
  extend ActiveSupport::Concern

  LIFETIME = 5.minutes
  PURPOSES = %w[sign_in second_factor confirm register].freeze
  SPENT_PURPOSE = "content_spiel passkey challenge".freeze

  private

  def issue_passkey_challenge(purpose, challenge)
    raise ArgumentError, "#{purpose.inspect} is not among #{PURPOSES}" unless PURPOSES.include?(purpose)

    session[:passkey_challenge] = { "purpose" => purpose, "challenge" => challenge, "at" => Time.current.to_i }
    nil
  end

  def take_passkey_challenge(purpose)
    raise ArgumentError, "#{purpose.inspect} is not among #{PURPOSES}" unless PURPOSES.include?(purpose)

    kept = session.delete(:passkey_challenge)
    return nil unless kept.is_a?(Hash) && kept["purpose"] == purpose && kept["challenge"].is_a?(String)
    return nil unless kept["at"].is_a?(Integer)

    left = LIFETIME.to_i - (Time.current.to_i - kept["at"])
    return nil unless left >= 0 && spend_passkey_challenge(purpose, kept["challenge"], left)

    kept["challenge"]
  end

  # True for the one take that wrote the challenge's spent mark.
  def spend_passkey_challenge(purpose, challenge, seconds_left)
    key = "passkey_challenge:spent:#{VisitorAddress.digest("#{purpose}:#{challenge}", purpose: SPENT_PURPOSE)}"
    SignIn.store.write(key, true, unless_exist: true, expires_in: [ seconds_left, 1 ].max) ? true : false
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
