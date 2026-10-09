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
    include AutosaveResponses

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

    # "Your name" (design pass spec §5.1) and the two Notes switches (notes
    # spec §6.4, D18, D19): one form, one footer, one save (notes handoff,
    # decision 13). Not `Users::Save` -- that needs `users.manage`;
    # `Users::UpdateProfile` is open to every user for their own account
    # only, and it is always `Current.user`: the request names nobody. A
    # switch the request does not send is left as it is (the form always
    # sends both, a hidden "0" ahead of each box).
    #
    # A success answers Turbo with a STREAM, not a redirect: the screen has a
    # second form (the password), and re-rendering the screen -- or the whole
    # shell, as the `_top` redirect did -- threw away whatever was typed into
    # it, after asking "Leave without saving?" about a save that had already
    # happened. The stream replaces the one thing a new name changes outside
    # the field itself, the sidebar's account block, and says "Name saved.";
    # the footer takes what it sent as its new baseline
    # (`admin--save-bar#submitEnded`). Without Turbo it is the redirect. The
    # new settings reach the scripts (`admin--notes-alert`, on <body>) with
    # the next page.
    #
    # A refusal draws the screen again with what was sent in the form
    # (`@profile_values`) and the account as it is STORED everywhere else:
    # the service leaves the refused values on the record, and the sidebar's
    # name and <body>'s settings must not show what was never saved.
    def update_profile
      result = Users::UpdateProfile.call(Current.user, name: params[:name], notes_sound: switch(:notes_sound), notes_desktop: switch(:notes_desktop))
      if result.ok?
        # Decided by "does the client take a stream", not `respond_to`: the
        # name is saved by now, and a client that accepts neither format must
        # not be told 406 about a save that happened. Everything else gets
        # the redirect.
        if request.accepts.any? { |type| type.symbol == :turbo_stream }
          render turbo_stream: [
            turbo_stream.replace("account-identity", Admin::Shell::AccountIdentityComponent.new(user: Current.user)),
            toast_stream("Name saved.")
          ]
        else
          redirect_to admin_account_password_path(**admin_url_options), status: :see_other, notice: "Name saved."
        end
      else
        @profile_errors = result.errors
        @profile_values = Current.user.slice(:name, :notes_sound, :notes_desktop).symbolize_keys
        Current.user.restore_attributes
        render :edit, status: :unprocessable_entity
      end
    end

    private

    # A switch as the form sends it: "1" on, anything else off, absent nil.
    def switch(name) = params.key?(name) ? params[name] == "1" : nil
  end
end
