module Admin
  # The Users module list, new/create,
  # edit/update (name, email, the groups, and a password only when one was
  # typed -- `Users::Save`'s own doc comment explains why a blank password
  # field means "leave it alone"), owner (the "Make owner…" / "Remove owner
  # rights…" action, the only request that changes the owner flag), sessions
  # ("End all sessions…", `Sessions::EndAll`), destroy
  # (refused for the last owner, `Users::Destroy` ->
  # `User#ensure_not_last_owner`). A permission refusal from `Users::Save` (a
  # group the actor can't assign, an owner or an outranking user changed by
  # someone who may not) is the 403 page. Inviting someone is
  # `Admin::InvitesController`: an invitation is no user until it is
  # accepted (`Invitation`); `new`/`create` here make a user with a password
  # set up front.
  #
  # Plain redirect-with-flash throughout, not autosave: a user's email and
  # password are exactly the kind of field an accidental keystroke-triggered
  # save (an autosaving form's whole point elsewhere) must never touch
  # silently -- an edit here is a deliberate "Save changes" submit.
  class UsersController < BaseController
    include StaleForm
    include UsersList

    # The whole module is `users.manage`; `Users::*` check it again, per user, for every write.
    before_action -> { require_permission("users.manage") }
    before_action :set_user, only: %i[edit update destroy owner sessions]

    def index
      load_users_list
    end

    def new
      @user = User.new
    end

    def create
      result = Users::Save.call(User.new, attributes: user_params)

      if result.ok?
        redirect_to edit_admin_user_path(result.record, **admin_url_options), status: :see_other, notice: t("admin.users.created")
      else
        forbidden_or(result) do
          @user = result.record
          render :new, status: :unprocessable_entity
        end
      end
    end

    def edit
      load_editor_extras
    end

    # A stale form (`Admin::StaleForm`: the user's `updated_at`, which a group
    # change from a group's editor moves too) is refused before the service runs;
    # the typed name, email and ticked groups stay in the form (a typed password
    # never comes back, by design).
    #
    # Not for a user the viewer can only view (`Users::Manageability` anything
    # but `:editable`): what they send is a forged write, and `Users::Save`
    # answers it with its 403 and one `access.denied`. A 409 first would record
    # nothing.
    def update
      if manageability(@user) == :editable && stale_form?(@user, params[:base_updated_at])
        @user.assign_attributes(user_params.slice(:name, :email_address))
        load_editor_extras
        return render_stale(:edit, @user)
      end

      result = Users::Save.call(@user, attributes: user_params)

      if result.ok?
        redirect_to edit_admin_user_path(@user, **admin_url_options), status: :see_other, notice: t("admin.users.saved")
      else
        forbidden_or(result) do
          @user = result.record
          load_editor_extras
          render :edit, status: :unprocessable_entity
        end
      end
    end

    # "Make owner…" / "Remove owner rights…" an instant
    # action, `owner=1|0`, answered by `Users::Save` and nothing else -- who may
    # change an owner flag, and that the last owner can't be demoted, are its
    # rules, asked again on this very request; the editor only decides whether to
    # show the button. A refusal is the 403 page (and one `access.denied`), a
    # failure the model's own ("can't demote the last owner") a toast on the editor.
    # Anything but "0" or "1" is no request at all: `Users::Save` casts a blank
    # value to nil, which differs from either flag and would flip it.
    def owner
      return head(:bad_request) unless %w[0 1].include?(params[:owner])

      was_owner = @user.owner?
      result = Users::Save.call(@user, attributes: { owner: params[:owner] })

      if result.ok?
        redirect_to edit_admin_user_path(@user, **admin_url_options), status: :see_other, notice: owner_notice(@user, was_owner)
      else
        forbidden_or(result) do
          redirect_to edit_admin_user_path(@user, **admin_url_options), status: :see_other, alert: result.errors.to_sentence # i18n-ok: a service's refusals, joined with the locale's support.array words
        end
      end
    end

    # "End all sessions…": an owner signs another user out everywhere,
    # answered by `Sessions::EndAll` alone -- the owner rule, the refusal of your
    # own account and the one `session.ended` event are its. A refusal is the 403
    # page; your own account is a plain failure, a toast on the editor.
    def sessions
      result = Sessions::EndAll.call(@user)

      if result.ok?
        redirect_to edit_admin_user_path(@user, **admin_url_options), status: :see_other, notice: t("admin.components.users_screen.sessions_zone.ended", name: @user.name_or_email)
      else
        forbidden_or(result) do
          redirect_to edit_admin_user_path(@user, **admin_url_options), status: :see_other, alert: result.errors.to_sentence # i18n-ok: a service's refusals, joined with the locale's support.array words
        end
      end
    end

    # Deleting yourself is allowed, as long as you're not the
    # last user -- `deleting_self` is captured *before* `Users::Destroy`
    # runs, since `@user` (and the session `Current.user` resolves through)
    # is gone by the time it returns successfully. There's no session left
    # to keep serving once your own account is gone, so this ends
    # it (`terminate_session`, the same helper `Admin::SessionsController#
    # destroy` uses for an ordinary sign-out) and lands on sign-in exactly
    # like one, instead of leaving a signed-in request pointed at a user row
    # that's already gone.
    def destroy
      deleting_self = @user == Current.user
      result = Users::Destroy.call(@user)

      if !result.ok?
        redirect_to admin_users_path(**admin_url_options), status: :see_other, alert: result.errors.to_sentence # i18n-ok: a service's refusals, joined with the locale's support.array words
      elsif deleting_self
        terminate_session
        redirect_to admin_sign_in_path, status: :see_other, notice: t("admin.users.deleted_own")
      else
        redirect_to admin_users_path(**admin_url_options), status: :see_other, notice: t("admin.users.deleted")
      end
    end

    private

    def owner_notice(user, was_owner)
      key = if user.owner? == was_owner
        user.owner? ? "already" : "not"
      else
        user.owner? ? "now" : "no_longer"
      end
      t("admin.users.owner.#{key}", name: user.name_or_email)
    end

    # What the editor draws beside the form: the last sign-in and, for an owner
    # viewer (the only one the sessions zone is drawn for), the open session count.
    def load_editor_extras
      @last_sign_in = Users::LastSignIn.for([ @user ])[@user.id]
      @open_sessions = @user.open_session_count if Current.user&.owner?
    end

    def set_user
      @user = User.find(params[:id])
    end

    # `group_ids` passes straight through: `Users::Save` decides who may change
    # it. There is no `owner` here: the flag changes only through
    # `PATCH users/:id/owner`, so a forged `user[owner]` is dropped as unpermitted
    # and the rest of the save is an ordinary one.
    def user_params
      params.fetch(:user, ActionController::Parameters.new).permit(:name, :email_address, :password, :password_confirmation, group_ids: [])
    end

    # What the editor may draw for `@user`: `:editable`,
    # `:owner_protected` or `:outranked` -- the very answer the services enforce,
    # so the page and the writes can't drift. It decides only what is rendered;
    # every refusal stays in `Users::Save`/`Users::Destroy`, which ask again.
    helper_method def manageability(user) = Users::Manageability.for(Current.actor, user)

    # Whether the owner toggle is locked because `user` is the last owner
    # (demoting them is refused anyway, by `User`'s own validation).
    helper_method def last_owner?(user)
      user.persisted? && user.owner_in_database && User.where(owner: true).count == 1
    end
  end
end
