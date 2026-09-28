module Admin
  # CS Studio's sign-in (cs-studio spec §3). Namespaced and routed under
  # ContentSpiel::ADMIN_PATH like every other admin controller, but not a
  # subclass of Admin::BaseController: that base sets `layout "admin"` and
  # `Current.channel = :admin` for signed-in screens, while sign-in itself
  # must render *before* a session exists, in the shared product layout the
  # setup wizard also uses.
  class SessionsController < ApplicationController
    layout "product"

    allow_unauthenticated_access only: %i[ new create ]
    rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to admin_sign_in_path, alert: "Try again later." }

    def new
    end

    # Sign-ins and sign-outs are audited (access-control design spec §4.3)
    # straight through `Audit.record` -- a session isn't a record any
    # service writes. `session.created`/`session.destroyed` are the user's
    # own (actor and subject both); `session.failed` has no user to name,
    # so it carries the email that was tried in `metadata` -- never the
    # password (Review Focus 5).
    def create
      if user = User.authenticate_by(params.permit(:email_address, :password))
        start_new_session_for user
        Current.actor = user
        Audit.record("session.created", subject: user)
        redirect_to after_authentication_url
      else
        Audit.record("session.failed", metadata: { "email_address" => params[:email_address].to_s })
        redirect_to admin_sign_in_path, alert: "Try another email address or password."
      end
    end

    def destroy
      Audit.record("session.destroyed", subject: Current.user)
      terminate_session
      redirect_to admin_sign_in_path, status: :see_other
    end
  end
end
