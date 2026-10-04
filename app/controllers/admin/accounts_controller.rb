module Admin
  # "Change my password" (access-control design spec §3.3 "Any user may
  # change their own password", §5): open to every signed-in user, from the
  # account menu -- the Users module, where an admin changes *other*
  # people's passwords, needs `users.manage`.
  #
  # The current password is required (`Users::UpdatePassword`'s
  # `current_password:`), so a session left signed in on someone else's
  # screen can't be turned into a takeover of the account. A success signs
  # out every *other* session of the user -- a password change is what
  # someone does when they think it leaked -- and keeps this one; the
  # service does that itself, together with the write
  # (`Users::OwnerProtection#end_sessions_after_password_change`).
  class AccountsController < BaseController
    # The current-password check is a password oracle; throttled like
    # sign-in and the reset flow.
    rate_limit to: 10, within: 3.minutes, only: :update, with: -> {
      redirect_to admin_account_password_path(**admin_url_options), status: :see_other, alert: "Try again later."
    }

    def edit
    end

    def update
      result = Users::UpdatePassword.call(Current.user,
        current_password: params[:current_password].to_s,
        password: params[:password], password_confirmation: params[:password_confirmation])

      if result.ok?
        redirect_to admin_account_password_path(**admin_url_options), status: :see_other, notice: "Password changed. Your other sessions were signed out."
      else
        @errors = result.errors
        # By field too, so the current-password message can sit under its own
        # input as well as in the summary. A denied result carries no record
        # errors, only its sentence.
        @field_errors = result.record.errors.to_hash(true)
        render :edit, status: :unprocessable_entity
      end
    end

    # "Your name" (design pass spec §5.1): the one profile field. Not
    # `Users::Save` -- that needs `users.manage`; `Users::UpdateProfile` is
    # open to every user for their own account only.
    def update_profile
      result = Users::UpdateProfile.call(Current.user, name: params[:name])
      if result.ok?
        redirect_to admin_account_password_path(**admin_url_options), status: :see_other, notice: "Name saved."
      else
        @profile_errors = result.errors
        render :edit, status: :unprocessable_entity
      end
    end
  end
end
