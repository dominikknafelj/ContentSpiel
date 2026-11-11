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
# challenge also spends it in `SignIn::SpentChallenge`, a table with a
# unique digest, in one atomic insert that does nothing on a duplicate: of
# any number of sends of one challenge, even at the same moment, exactly
# one inserts the row and is let through. A database error is no spend, so
# the challenge is refused. The row lives a second past the challenge's
# own lifetime, so it never lapses before the challenge does, and sits in
# a table so that no cache eviction can drop it. The digest is an HMAC of
# the purpose and the challenge, never the challenge itself. Every purpose
# is taken this way, and a challenge is spent whatever its answer turns out
# to be.
#
# The challenge reaches no page, span or log line: it is only in the cookie,
# which the browser cannot read, and the table holds only its HMAC.
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

    expires_at = Time.zone.at(kept["at"] + LIFETIME.to_i)
    return nil unless expires_at >= Time.current && spend_passkey_challenge(purpose, kept["challenge"], expires_at)

    kept["challenge"]
  end

  # True for the one take that inserted the challenge's digest.
  def spend_passkey_challenge(purpose, challenge, expires_at)
    digest = VisitorAddress.digest("#{purpose}:#{challenge}", purpose: SPENT_PURPOSE)
    SignIn::SpentChallenge.spend!(digest, expires_at: expires_at + 1.second)
  rescue ActiveRecord::ActiveRecordError => error
    # Refused, never let through: only the class of the error is logged.
    Rails.logger.warn("[passkey] a challenge could not be spent (#{error.class}), so it is refused")
    false
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
