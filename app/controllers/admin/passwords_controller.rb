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
        PasswordsMailer.reset(user).deliver_later
      end

      redirect_to admin_sign_in_path, notice: "Password reset instructions sent (if user with that email address exists)."
    end

    def edit
    end

    def update
      if @user.update(params.permit(:password, :password_confirmation))
        @user.sessions.destroy_all
        redirect_to admin_sign_in_path, notice: "Password has been reset."
      else
        redirect_to admin_edit_password_path(params[:token]), alert: "Passwords did not match."
      end
    end

    private
      def set_user_by_token
        @user = User.find_by_password_reset_token!(params[:token])
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        redirect_to new_admin_password_path, alert: "Password reset link is invalid or has expired."
      end
  end
end
