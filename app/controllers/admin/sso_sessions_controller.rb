module Admin
  # Signing in to CS Studio through the site's single sign-on provider
  # (OpenID Connect, `SignIn::Oidc`): `create`, the sign-in page's button,
  # sends the person to the provider (`SsoStarts#start_sso`), and
  # `callback` takes the provider's answer, decides whose account it is
  # (`Sso::Admit`) and signs that person in. Outside `Admin::BaseController`,
  # on the product layout, before any session exists, as sign-in itself is.
  # With no provider configured both actions are 404.
  #
  # THE CALLBACK, in order, inside one `auth.sso.callback` span:
  #
  # 1. the kept state is taken from its cookie, once (`take_sso_state`:
  #    its age, and its spend; the cookie goes whatever the answer);
  # 2. `SignIn::Oidc::Callback` compares the provider's `state` with the
  #    kept one, exchanges the code with the kept PKCE verifier and checks
  #    the ID token against the kept nonce;
  # 3. `Sso::Admit` finds the account the identity signs into, with the
  #    invitation the start was made from when it is still open;
  # 4. `complete_sign_in` signs the person in, by the `sso` method, with the
  #    provider's refresh token on the session.
  #
  # THE ANSWERS. Every one is a redirect, and none says whether an account
  # exists:
  #
  #   unfinished      the sign-in page, "Signing in with %{provider} didn't
  #                   finish. Try again.": cancelled at the provider, a
  #                   provider error, a state that was missing, late, spent
  #                   or another browser's, a code or ID token that did not
  #                   hold, or a provider out of reach. Nothing is audited
  #                   (nobody is named, and a bot's run would bury the log);
  #                   the span says which (`auth.sso.reason`).
  #   refused         the sign-in page, "Your %{provider} account can't sign
  #                   in to this site. Ask an owner to invite you.": one
  #                   sentence for no account, an unverified email, an
  #                   owner's address and a linked account's address under
  #                   another subject. `Sso::Admit` records `sso.refused`.
  #   mismatch        a start from an invitation whose verified email is not
  #                   the invitation's: the invitation page, with
  #                   `flash[:sso_mismatch]` holding both addresses for the
  #                   page to name. Nothing is recorded.
  #   signed in       CS Studio, or the page the person was sent from
  #                   (`after_authentication_url`). `session.created` says
  #                   `{ "method" => "sso" }`. Someone else signed in in
  #                   this browser is signed out first, as an accepted
  #                   invitation does it: the browser is the new person's.
  #   limited         past the per-address rate limit, the sign-in page with
  #                   "Try again later.".
  #
  # CROSS-SITE, ON PURPOSE. The callback is a GET the provider's site sends
  # the browser to, so it carries no form token and needs none: what ties
  # it to this browser is the state, kept in a SameSite=Lax cookie (Strict
  # would not be sent on that navigation; `SsoStarts` says more) and
  # compared by `Callback`, and the nonce, which ties the ID token to the
  # same start. `create` is a POST from the sign-in page and carries the
  # form's token as every POST does.
  #
  # NO SECRET IS SEEN OUTSIDE ITS PLACE. The code and the state reach the
  # log masked (`filter_parameters`: `code`, `state`; the nonce in the
  # redirect's logged address, `nonce`) and no span (`Telemetry::
  # PathScrubber` replaces the request's query); the nonce, the verifier
  # and the tokens reach neither.
  class SsoSessionsController < ApplicationController
    include SsoStarts
    include SignInCompletion

    layout "product"

    allow_unauthenticated_access
    before_action :require_sso_provider
    # The per-address bucket, on a count of its own (`name:`), keyed as
    # sign-in keys an address: a start writes a cookie and asks the
    # provider's discovery, a callback asks its token endpoint, so a bot
    # must not make this site call out without bound.
    rate_limit to: 20, within: 3.minutes, name: "sso", store: SignIn.store,
      by: -> { VisitorAddress.key(request.remote_ip, purpose: SessionsController::RATE_LIMIT_PURPOSE) },
      with: -> { redirect_to admin_sign_in_path, alert: t("admin.sessions.limited") }

    def create
      start_sso(intent: "sign_in")
    end

    def callback
      Telemetry.in_span("auth.sso.callback", attributes: { "auth.sso.issuer_host" => sso_provider.issuer_host.to_s }) do |span|
        started_at = Time.current
        kept = take_sso_state
        result = SignIn::Oidc::Callback.new(provider: sso_provider, redirect_uri: sso_redirect_uri)
          .call(params: callback_params, kept: kept)
        next unfinished(span, result.reason) unless result.ok

        admit(span, result.identity, invitation: kept_invitation(kept), started_at: started_at)
      end
    end

    private

    def require_sso_provider
      head :not_found if sso_provider.nil?
    end

    # The three a provider sends back, as they came: `Callback` takes
    # anything that is no string for none.
    def callback_params = params.to_unsafe_h.slice("code", "state", "error")

    # The invitation the start was made from, while it is still open: one
    # withdrawn, accepted or lapsed since is none, and the identity is
    # matched as a sign-in's.
    def kept_invitation(kept)
      return unless kept["intent"] == "invitation" && kept["invitation_id"].is_a?(Integer)

      invitation = Invitation.open.find_by(id: kept["invitation_id"])
      invitation unless invitation.nil? || invitation.expired?
    end

    def admit(span, identity, invitation:, started_at:)
      result = Sso::Admit.call(identity, invitation: invitation)
      return mismatch(span, invitation, result.errors.last) if result.errors.first == Sso::Admit::MISMATCH
      return refused(span, result.errors.first) unless result.ok?

      user = result.record
      # `Sso::Admit` never answers an owner; were one answered, it is refused
      # here, before anyone signed in in this browser is signed out, and
      # recorded as Admit records an owner. `complete_sign_in` refuses it
      # too, for every outside method.
      return refused_owner(span, identity) if user.owner?

      terminate_session if resume_session
      complete_sign_in(user, method: "sso", provider_token: identity.refresh_token)

      Telemetry.record(span, "auth.outcome" => "ok")
      # An account made by this very callback says so with the toast a
      # password acceptance shows (`InvitationsController#update`).
      notice = t("invitations.update.ready") if accepted_now?(user, since: started_at)
      redirect_to after_authentication_url, notice: notice
    end

    # Whether `user` is the account an invitation made during this callback
    # (an existing account signing in, or one linked by its email, is not).
    def accepted_now?(user, since:)
      Invitation.accepted.exists?(user_id: user.id, accepted_at: since..)
    end

    def unfinished(span, reason)
      Telemetry.record(span, "auth.outcome" => "unfinished", "auth.sso.reason" => reason)
      redirect_to admin_sign_in_path, alert: t("admin.sessions.sso_unfinished", provider: sso_provider.name)
    end

    # The span takes the reason only when it is one of the account reasons'
    # words (`SPAN_REASONS`): any other failure a service answers is
    # sentences, which reach no span.
    def refused(span, reason)
      reason = reason.to_s
      Telemetry.record(span, { "auth.outcome" => "refused", "auth.sso.reason" => (reason if SignIn::Oidc::ACCOUNT_REASONS.include?(reason)) }.compact)
      redirect_to admin_sign_in_path, alert: t("admin.sessions.sso_refused", provider: sso_provider.name)
    end

    # `sso.refused` as `Sso::Admit` writes it: nobody's, the provider's email
    # cut to an address's length and only when it gave one.
    def refused_owner(span, identity)
      email = User.normalize_value_for(:email_address, identity.email.to_s)
      metadata = { "reason" => Sso::Admit::OWNER, "issuer_host" => identity.issuer_host }
      metadata["email"] = email.first(Sso::Admit::EMAIL_LIMIT) if email.present?
      Current.actor = nil
      Audit.record("sso.refused", metadata: metadata)
      refused(span, Sso::Admit::OWNER)
    end

    # The invitation page draws both addresses (`flash[:sso_mismatch]`): the
    # one the provider signed in and the one invited.
    def mismatch(span, invitation, email)
      Telemetry.record(span, "auth.outcome" => "refused", "auth.sso.reason" => SignIn::Oidc::MISMATCH_REASON)
      flash[:sso_mismatch] = { "got" => email, "email" => invitation.email_address }
      redirect_to admin_invitation_path
    end
  end
end
