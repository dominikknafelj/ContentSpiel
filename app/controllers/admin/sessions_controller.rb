module Admin
  # CS Studio's sign-in (cs-studio spec §3). Namespaced and routed under
  # ContentSpiel::ADMIN_PATH like every other admin controller, but not a
  # subclass of Admin::BaseController: that base sets `layout "admin"` and
  # `Current.channel = :admin` for signed-in screens, while sign-in itself
  # must render *before* a session exists, in the shared product layout the
  # setup wizard also uses.
  class SessionsController < ApplicationController
    layout "product"

    # The longest an email address can be (RFC 5321's path limit), and so
    # the most of one `session.failed` keeps.
    MAX_EMAIL_LENGTH = 254

    allow_unauthenticated_access only: %i[ new create ]
    rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to admin_sign_in_path, alert: "Try again later." }

    def new
    end

    # Sign-ins and sign-outs are audited (access-control design spec §4.3)
    # straight through `Audit.record` -- a session isn't a record any
    # service writes. `session.created`/`session.destroyed` are the user's
    # own (actor and subject both); `session.failed` has no user to name,
    # so it carries the email that was tried in `metadata` -- never the
    # password (Review Focus 5). Nor a password typed into the email box by
    # mistake: a value without an "@" isn't an address, so nothing is kept
    # (final fix wave, Minor 4); an address is cut to the 254 characters
    # an email address can have, so the log can't be stuffed through it.
    def create
      # `can_sign_in`: an invited row holds the digest of a password nobody was
      # told, and is never reached by a typed one (docs/reference/mail.md).
      if user = User.can_sign_in.authenticate_by(params.permit(:email_address, :password))
        start_new_session_for user
        Current.actor = user
        Audit.record("session.created", subject: user)
        redirect_to after_authentication_url
      else
        Audit.record("session.failed", metadata: failed_sign_in_metadata)
        redirect_to admin_sign_in_path, alert: "Try another email address or password."
      end
    end

    def destroy
      Audit.record("session.destroyed", subject: Current.user)
      terminate_session
      redirect_to admin_sign_in_path, status: :see_other
    end

    private

    def failed_sign_in_metadata
      email = params[:email_address].to_s
      email.include?("@") ? { "email_address" => email.first(MAX_EMAIL_LENGTH) } : {}
    end
  end
end
