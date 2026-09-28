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
  # someone does when they think it leaked -- and keeps this one.
  class AccountsController < BaseController
    def edit
    end

    def update
      result = Users::UpdatePassword.call(Current.user,
        current_password: params[:current_password].to_s,
        password: params[:password], password_confirmation: params[:password_confirmation])

      if result.ok?
        Current.user.sessions.where.not(id: Current.session.id).destroy_all
        redirect_to admin_account_password_path(**admin_url_options), status: :see_other, notice: "Password changed. Your other sessions were signed out."
      else
        @errors = result.errors
        render :edit, status: :unprocessable_entity
      end
    end
  end
end
