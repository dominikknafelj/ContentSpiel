module Admin
  # Enrolment's gate: a session the passkey policy covered when it started
  # (`Session#enrolment_due`, decided once by `start_new_session_for`), whose
  # person held no passkey then, reaches nothing of CS Studio or the preview
  # but the enrolment page until a passkey is added (`SignIn::Passkeys::Add` clears
  # the mark on every session of the person). A policy changed later reaches
  # nobody's open session: only the next sign-in reads it.
  #
  # A request the gate holds is answered by what it is:
  # - a page (a GET or HEAD for HTML, no XHR): a redirect to enrolment, the
  #   address kept as the sign-in's return address, so the codes' Done goes
  #   where the person was going;
  # - Turbo's own GET or a frame's (`turbo_get?`): a page Turbo may not draw,
  #   so the address is loaded whole and meets the redirect above;
  # - anything else (a write, a script's fetch, JSON): 403, nothing done.
  #
  # Where the request has no relying party (an IP address in development,
  # `SignIn::Passkeys::RelyingParty`), no passkey can be made, so nothing is held.
  #
  # WHAT IT SKIPS, all of it what enrolment itself needs:
  # - `Admin::EnrolmentsController`, the page;
  # - `Admin::PasskeysController#options` and `#create`, the add the page
  #   sends (its rename and remove stay held: Your account is not reachable);
  # - `Admin::ConfirmationsController`, Confirm it's you, which the add asks
  #   for once the sign-in is more than Session::CONFIRM_WINDOW old.
  # Sign out is `Admin::SessionsController`, which is outside
  # `Admin::BaseController` and never meets the gate.
  module PasskeyEnrolment
    extend ActiveSupport::Concern

    included do
      before_action :require_passkey_enrolment
    end

    private

    def require_passkey_enrolment
      return unless Current.session&.enrolment_due?
      return if SignIn::Passkeys::RelyingParty.for(request_origin: request.base_url, name: request.host).nil?

      if turbo_get?
        load_whole_page
      elsif page_request?
        session[:return_to_after_authenticating] = request.url
        redirect_to admin_enrolment_path
      else
        head :forbidden, content_type: "text/plain"
      end
    end
  end
end
