module Admin
  # CS Studio's password reset (cs-studio spec §3) -- see the comment on
  # Admin::SessionsController for why this isn't an Admin::BaseController.
  class PasswordsController < ApplicationController
    layout "product"

    allow_unauthenticated_access
    # No page of the new-password form is kept by a cache: the refused form
    # (422) carries the token in its hidden field, and the empty page must
    # not be answerable from a copy of that one. `no-store` also keeps both
    # out of the browser's back/forward cache.
    before_action :no_store, only: %i[ edit legacy check update ]
    before_action :set_user_by_token, only: :update
    rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_admin_password_path, alert: "Try again later." }
    # The early check has the request form's limit, counted on its own
    # (`name:`), so that asking for links and opening them do not use each
    # other up. Past it the answer is a bare 429, which the page's script
    # takes as "not known": it shows the form, and `update` decides.
    rate_limit to: 10, within: 3.minutes, only: :check, name: "check", with: -> { head :too_many_requests }

    def new
    end

    def create
      if user = User.find_by(email_address: params[:email_address])
        # The link in the mail is the site's configured address when there
        # is one, and then the request's origin is not handed over at all
        # (it is whatever Host this request named). Without one, and in
        # development and test only (`PasswordsMailer.request_origin_used?`,
        # which says why), this request's origin is the only address anybody
        # knows: a String, because a job delivers the mail, which
        # `PasswordsMailer` parses before it uses any of it. Anywhere else
        # without an address the mailer builds no mail and logs why; the
        # answer below is the same words either way.
        PasswordsMailer.reset(user, **reset_mail_origin).deliver_later
      end

      # The "sent" state is a param on the request page, not a flash and not
      # something the lookup decides: a known and an unknown address take the
      # same redirect and render the same words, so the page can't be used
      # to find out which addresses have an account.
      redirect_to new_admin_password_path(sent: 1)
    end

    # THE TOKEN IS IN NO ADDRESS (safe-address spec §4). The mailed link is
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

    # The link as it was mailed before, `password/<token>/edit`: redirected
    # to the page WITHOUT the token. A server cannot hand a browser a
    # fragment it was never sent, and must not repeat the token in another
    # address; the page then says the link is incomplete and offers a new
    # one. The redirect's `Location`, its body and the parameters line of
    # the log hold no token. The request's own first log line does hold the
    # path it was asked for, as the proxy's access log does: nothing is
    # done about that, because such a link exists only in a mail sent
    # before this change, for the fifteen minutes its token is good.
    def legacy
      redirect_to admin_edit_password_path, status: :found
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
        redirect_to admin_sign_in_path, notice: "Password has been reset."
      else
        # Rendered, not redirected: the form needs the token again, and a
        # redirect could carry it only in an address or in the session. It
        # is in the hidden field of this one response, to the person who
        # just sent it (and it is the token `set_user_by_token` verified, so
        # a String). `no_store` (below) keeps the response out of every
        # cache.
        @token = params[:token]
        flash.now[:alert] = result.errors.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    private
      def reset_mail_origin
        return {} if SiteAddress.current.configured? || !PasswordsMailer.request_origin_used?

        { origin: request.base_url }
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

      # `expired` selects the "This link has expired" state of the request
      # page (a bad signature and a lapsed 15 minutes look the same).
      def set_user_by_token
        @user = user_for_token
        redirect_to new_admin_password_path(expired: 1) unless @user
      end
  end
end
