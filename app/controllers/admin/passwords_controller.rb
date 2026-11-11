module Admin
  # CS Studio's password reset -- see the comment on
  # Admin::SessionsController for why this isn't an Admin::BaseController.
  class PasswordsController < ApplicationController
    include MailLinkOrigin

    layout "product"

    allow_unauthenticated_access
    # No page of the new-password form is kept by a cache: the refused form
    # (422) carries the token in its hidden field, and the empty page must
    # not be answerable from a copy of that one. `no-store` also keeps both
    # out of the browser's back/forward cache.
    before_action :no_store, only: %i[ edit check update ]
    before_action :set_user_by_token, only: :update
    # Only the REQUEST (`new`, `create`) follows mail: `edit`, `check` and
    # `update` keep working whatever the state, so a person holding a valid
    # link finishes even if an owner has just changed the settings.
    before_action :require_mail_ready, only: %i[ new create ]
    rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_admin_password_path, alert: t("admin.passwords.limited") }
    # The early check has the request form's limit, counted on its own
    # (`name:`), so that asking for links and opening them do not use each
    # other up. Past it the answer is a bare 429, which the page's script
    # takes as "not known": it shows the form, and `update` decides.
    rate_limit to: 10, within: 3.minutes, only: :check, name: "check", with: -> { head :too_many_requests }

    def new
    end

    # THE REQUEST LOOKS NOBODY UP. Whether the address has an account is
    # the job's question (`PasswordResetRequestJob`, which finds the user and
    # queues the reset mail through `ApplicationMailer.queue`): here a known
    # and an unknown address enqueue the same one job and take the same
    # redirect, so neither the answer nor the time it takes says which
    # addresses have an account. A lookup here, and an enqueue for a known
    # address alone, would be a database write's difference in time. The
    # address goes as the String typed, or "" for anything else (a list, a
    # hash, nothing), which no account has.
    #
    # The link in the mail is the site's configured address when there is
    # one, else the request's origin in development and test only
    # (`Admin::MailLinkOrigin`, which says why); anywhere else without an
    # address the mailer builds no mail and logs why, and the answer is the
    # same words either way.
    #
    # The "sent" state is a param on the request page, not a flash and not
    # something the lookup decides: the page renders the same words for
    # every address.
    def create
      email = params[:email_address]
      PasswordResetRequestJob.perform_later(email.is_a?(String) ? email : "", **mail_link_origin)

      redirect_to new_admin_password_path(sent: 1)
    end

    # THE TOKEN IS IN NO ADDRESS. The mailed link is
    # `password/edit#<token>`; a browser sends what follows the "#" to no
    # server, so this action is never told it: no lookup, the same page for
    # everyone. The page's script (`reset-token`) moves the token from the
    # address into the form's hidden field, and `update` reads it from the
    # form's body, where `filter_parameters` masks it in the log. Whether
    # the link is good is therefore answered when the form is sent, not
    # before. A `token` parameter handed to THIS action is ignored: it would
    # be a token in an address.
    def edit
    end

    # THE EARLY CHECK. The page cannot know whether its link is good (it is
    # drawn without the token), and `update` says so only after a password
    # was typed twice. So the page's script asks here once, as soon as it
    # has moved the token out of the address: a POST with the token in its
    # body, never in an address, masked in the log like `update`'s.
    #
    # The answer is a status and nothing else, and says no more than
    # `update` would: 204 for a token `update` would take now, 410 for every
    # other (`user_for_token`: one answer whatever is wrong with it). It
    # writes nothing: no session key, no audit event, no change to the user,
    # and a good token is as good afterwards. It is advice to the page, not
    # the rule: a token can lapse while a password is typed, and a request
    # that never arrives leaves the form as it is, so `update` checks again
    # whatever was answered here.
    def check
      head user_for_token ? :no_content : :gone
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
        redirect_to admin_sign_in_path, notice: t("admin.passwords.reset")
      else
        # Rendered, not redirected: the form needs the token again, and a
        # redirect could carry it only in an address or in the session. It
        # is in the hidden field of this one response, to the person who
        # just sent it (and it is the token `set_user_by_token` verified, so
        # a String). `no_store` (Rails' own, the `before_action` above)
        # keeps the response out of every cache. The service's messages are
        # whole sentences: the alert above the form says them all, a line
        # each, and each field says its own under it (`@field_errors`).
        @token = params[:token]
        @field_errors = result.record.errors.to_hash(true)
        flash.now[:alert] = result.errors
        render :edit, status: :unprocessable_entity
      end
    end

    private
      # A bookmarked request page must not pretend to send. The one thing
      # said is that a link has lapsed (`expired`, where `update` or the
      # page's early check sends someone), because that person otherwise
      # lands on sign-in with no word about why.
      def require_mail_ready
        return if MailSettings.current.ready?

        if params[:expired] == "1" && action_name == "new"
          redirect_to admin_sign_in_path, alert: t("admin.passwords.expired_without_mail")
        else
          redirect_to admin_sign_in_path
        end
      end

      # The user a token from a request's body stands for, or nil. Anything
      # that is not a signed token of a user as they are now is ONE answer:
      # tampered, lapsed, used (it is signed over the password it was
      # mailed for), blank, missing, a list or a hash where a string
      # belongs, and a good token of a user who has been deleted since
      # (Active Record looks the id up before it compares anything, and
      # raises `RecordNotFound` for that one, which would be a 404).
      def user_for_token
        token = params[:token]
        return unless token.is_a?(String) && token.present?

        User.find_by_password_reset_token!(token)
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
        nil
      end

      # `expired` selects the "This reset link has expired" state of the
      # request page (a bad signature and a lapsed 15 minutes look the same);
      # while mail is not ready that page is closed, and `require_mail_ready`
      # says the same on sign-in instead (`expired_without_mail`).
      def set_user_by_token
        @user = user_for_token
        redirect_to new_admin_password_path(expired: 1) unless @user
      end
  end
end
