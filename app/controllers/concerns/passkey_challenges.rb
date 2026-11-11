# The challenge a WebAuthn ceremony is answered to, kept between the options
# a browser is handed and the answer it sends back.
#
# It is kept in the Rails session (the encrypted cookie store) under
# `:passkey_challenge`, as `{ "purpose", "challenge", "at" }`, one at a time.
# A challenge is taken once, whatever the answer: `take_passkey_challenge`
# deletes it before it decides, so an assertion sent twice meets no challenge
# the second time even when its counter moved forward (`SignIn::PasskeyCheck`
# alone would pass it). One older than LIFETIME, or issued for another
# purpose (a registration's sent to sign-in), is no challenge, and the
# answer is refused as a wrong passkey. A page left open past the lifetime
# needs one more press: its script fetches fresh options after a refusal.
#
# The challenge reaches no page, span or log line: it is only in the cookie,
# which the browser cannot read.
module PasskeyChallenges
  extend ActiveSupport::Concern

  LIFETIME = 5.minutes
  PURPOSES = %w[sign_in second_factor confirm register].freeze

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
    return nil unless kept["at"].is_a?(Integer) && Time.current.to_i - kept["at"] <= LIFETIME.to_i

    kept["challenge"]
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
