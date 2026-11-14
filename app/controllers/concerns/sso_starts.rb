# Sending a person to the site's single sign-on provider, and taking back
# what was kept for the provider's answer: shared by the sign-in page's
# button (`Admin::SsoSessionsController#create`) and the invitation page's
# (`InvitationsController`), whose callback is the one
# `Admin::SsoSessionsController#callback`.
#
# THE REDIRECT URI is built once, here (`sso_redirect_uri`): the callback's
# route on CS Studio's own address when there is one (`ADMIN_HOST`), else the
# site's (`PUBLIC_HOST`), else, in development and test, the request's
# origin (`SignIn::Sso.callback_origin`). The start and the callback hand
# the same string to `Authorization.start` and `Callback.new`, since the
# token endpoint refuses a code exchanged under another redirect URI than
# the one it was issued to.
#
# THE STATE'S COOKIE, STATE_COOKIE, holds `{ "state", "nonce", "verifier",
# "at", "intent", "invitation_id" }`, encrypted and signed
# (`cookies.encrypted`), HttpOnly, Secure over HTTPS (always, in
# production, which forces HTTPS), pathed to STATE_PATH so it is sent to the
# callback and to no other address, and dropped by the browser after
# `SignIn::Sso::STATE_LIFETIME`, which the server checks against `at`
# besides. It is SAMESITE LAX, unlike the passkey challenges' Strict: the
# provider sends the person back with a top-level GET from its own site, a
# cross-site navigation, on which a Strict cookie is not sent and every
# callback would end as a bad state. Lax still keeps it from every
# cross-site subrequest and POST. The nonce and the verifier are secrets
# until the callback spends them, and they live nowhere else: no session,
# no table, no page.
#
# TAKEN ONCE (`take_sso_state`): the cookie is deleted whatever the answer,
# and the state is spent in `SignIn::SpentChallenge` under the purpose
# "sso", so a callback sent again with a copy of the cookie (another tab, a
# replay of a captured answer) finds it spent. Whether the provider sent
# back THIS state is not decided here: `SignIn::Sso::Callback` alone
# compares the `state` parameter with the kept one, in constant time.
#
# The including controller is under the admin path's routes and on the
# product layout; `start_sso` answers every request it is called for.
module SsoStarts
  STATE_COOKIE = :cs_sso_state
  STATE_PURPOSE = "sso".freeze
  INTENTS = %w[sign_in invitation].freeze

  # The cookie's path: the start writes it, only the callback reads it.
  def self.state_path = "/#{ContentSpiel::ADMIN_PATH}/sign-in/sso"

  private

  # The site's provider, or nil when single sign-on is not configured.
  def sso_provider
    return @sso_provider if defined?(@sso_provider)

    @sso_provider = SignIn::Sso::Provider.current
  end

  def sso_redirect_uri
    @sso_redirect_uri ||= admin_sso_callback_url(**SignIn::Sso.callback_origin(request_origin: request.base_url))
  end

  # Sends the person to the provider, keeping the request's three values in
  # STATE_COOKIE. A provider whose discovery cannot be read is the
  # unfinished sentence, on the page the start was pressed on: the sign-in
  # page, or the invitation page for an invitation's start.
  def start_sso(intent:, invitation: nil)
    raise ArgumentError, "#{intent.inspect} is not among #{INTENTS}" unless INTENTS.include?(intent)

    Telemetry.in_span("auth.sso.redirect", attributes: { "auth.sso.intent" => intent, "auth.sso.issuer_host" => sso_provider.issuer_host.to_s }) do |span|
      authorization = SignIn::Sso::Authorization.start(provider: sso_provider, redirect_uri: sso_redirect_uri)
      keep_sso_state(authorization, intent: intent, invitation: invitation)
      # The provider's own endpoint, from its discovery document, never a
      # parameter of this request.
      redirect_to authorization.url, allow_other_host: true, status: :see_other
    rescue SignIn::Sso::Unavailable => error
      Telemetry.record(span, "error.type" => SignIn::Sso.error_type(error))
      unfinished = t("admin.sessions.sso_unfinished", provider: sso_provider.name)
      if intent == "invitation"
        # The invitation page draws it alone (`flash[:sso_unfinished]`).
        flash[:sso_unfinished] = unfinished
        redirect_to admin_invitation_path, status: :see_other
      else
        redirect_to admin_sign_in_path, alert: unfinished, status: :see_other
      end
    end
  end

  def keep_sso_state(authorization, intent:, invitation:)
    cookies.encrypted[STATE_COOKIE] = {
      value: {
        "state" => authorization.state, "nonce" => authorization.nonce, "verifier" => authorization.verifier,
        "at" => Time.current.to_i, "intent" => intent, "invitation_id" => invitation&.id
      },
      httponly: true, same_site: :lax, secure: request.ssl?, path: SsoStarts.state_path,
      expires: SignIn::Sso::STATE_LIFETIME
    }
  end

  # The kept values (String keys), or nil: no cookie, one that does not
  # open, one whose `at` is older than STATE_LIFETIME, or one whose state was
  # spent before. The cookie is deleted in every case.
  def take_sso_state
    kept = cookies.encrypted[STATE_COOKIE]
    cookies.delete(STATE_COOKIE, path: SsoStarts.state_path)
    return unless kept.is_a?(Hash) && kept["state"].is_a?(String) && kept["at"].is_a?(Integer)

    expires_at = Time.zone.at(kept["at"]) + SignIn::Sso::STATE_LIFETIME
    return unless Time.current <= expires_at
    # The spent mark outlives the state by a second, so it never lapses
    # before the state would be refused as late anyway.
    return unless SignIn::SpentChallenge.take(purpose: STATE_PURPOSE, value: kept["state"], expires_at: expires_at + 1.second)

    kept
  end
end
