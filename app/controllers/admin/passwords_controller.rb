module Admin
  # CS Studio's password reset (cs-studio spec §3) -- see the comment on
  # Admin::SessionsController for why this isn't an Admin::BaseController.
  class PasswordsController < ApplicationController
    layout "product"

    allow_unauthenticated_access
    before_action :set_user_by_token, only: %i[ edit update ]
    rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_admin_password_path, alert: "Try again later." }

    def new
    end

    def create
      if user = User.find_by(email_address: params[:email_address])
        # The link in the mail is the site's configured address when there
        # is one, and then the request's origin is not handed over at all
        # (it is whatever Host this request named). Without one, this
        # request's origin is the only address anybody knows: a String,
        # because a job delivers the mail, which `PasswordsMailer` parses
        # before it uses any of it.
        PasswordsMailer.reset(user, **reset_mail_origin).deliver_later
      end

      # The "sent" state is a param on the request page, not a flash and not
      # something the lookup decides: a known and an unknown address take the
      # same redirect and render the same words, so the page can't be used
      # to find out which addresses have an account.
      redirect_to new_admin_password_path(sent: 1)
    end

    def edit
    end

    def update
      # `actor: @user`: nobody is signed in here (a nil actor on `:admin`
      # is denied), but the emailed reset token `set_user_by_token` just
      # verified authenticated this request as @user -- so it's their own
      # password change, which `Users::UpdatePassword` allows and records
      # as theirs. The service also ends every session of the user with the
      # write (`keep_acting_session: false`: the token made this change, so
      # not even a session signed in in this browser is kept).
      result = Users::UpdatePassword.call(@user, password: params[:password], password_confirmation: params[:password_confirmation],
        actor: @user, keep_acting_session: false)

      if result.ok?
        redirect_to admin_sign_in_path, notice: "Password has been reset."
      else
        redirect_to admin_edit_password_path(params[:token]), alert: result.errors.to_sentence
      end
    end

    private
      def reset_mail_origin
        SiteAddress.current.configured? ? {} : { origin: request.base_url }
      end

      def set_user_by_token
        @user = User.find_by_password_reset_token!(params[:token])
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        # `expired` selects the "This link has expired" state of the request
        # page (a bad signature and a lapsed 15 minutes look the same).
        redirect_to new_admin_password_path(expired: 1)
      end
  end
end
