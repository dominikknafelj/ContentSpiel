module Admin
  # The Users module (cs-studio spec §6.1, Task 8): list, new/create,
  # edit/update (email, and a password only when one was typed --
  # `Users::Save`'s own doc comment explains why a blank password field
  # means "leave it alone"), destroy (refused for the last user,
  # `Users::Destroy` -> `User#ensure_not_last_owner`). Invites stay on the
  # roadmap (spec §6.1) -- there is no separate "invite" action here, only
  # `new`/`create` with a password set up front.
  #
  # Plain redirect-with-flash throughout, not autosave: a user's email and
  # password are exactly the kind of field an accidental keystroke-triggered
  # save (an autosaving form's whole point elsewhere) must never touch
  # silently -- an edit here is a deliberate "Save changes" submit.
  class UsersController < BaseController
    # The whole module is `users.manage` (access-control design spec §3.3
    # "Users"); `Users::*` check it again, per user, for every write.
    before_action -> { require_permission("users.manage") }
    before_action :set_user, only: %i[edit update destroy]

    def index
      @users = User.order(:email_address)
    end

    def new
      @user = User.new
    end

    def create
      result = Users::Save.call(User.new, attributes: user_params)

      if result.ok?
        redirect_to admin_users_path(**admin_url_options), status: :see_other, notice: "User created"
      else
        @user = result.record
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      result = Users::Save.call(@user, attributes: user_params)

      if result.ok?
        redirect_to admin_users_path(**admin_url_options), status: :see_other, notice: "User updated"
      else
        @user = result.record
        render :edit, status: :unprocessable_entity
      end
    end

    # Deleting yourself is allowed (spec §6.1), as long as you're not the
    # last user -- `deleting_self` is captured *before* `Users::Destroy`
    # runs, since `@user` (and the session `Current.user` resolves through)
    # is gone by the time it returns successfully. There's no session left
    # to keep serving once your own account no longer exists, so this ends
    # it (`terminate_session`, the same helper `Admin::SessionsController#
    # destroy` uses for an ordinary sign-out) and lands on sign-in exactly
    # like one, instead of leaving a signed-in request pointed at a user row
    # that's already gone.
    def destroy
      deleting_self = @user == Current.user
      result = Users::Destroy.call(@user)

      if !result.ok?
        redirect_to admin_users_path(**admin_url_options), status: :see_other, alert: result.errors.to_sentence
      elsif deleting_self
        terminate_session
        redirect_to admin_sign_in_path, status: :see_other, notice: "Your account was deleted"
      else
        redirect_to admin_users_path(**admin_url_options), status: :see_other, notice: "User deleted"
      end
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.fetch(:user, ActionController::Parameters.new).permit(:email_address, :password, :password_confirmation)
    end
  end
end
