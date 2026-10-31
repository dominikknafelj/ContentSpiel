module Admin
  # Invites on the Users screen (mail spec "Invites", design answer M4):
  # "Invite person" (`create`, from the dialog), and an invited row's menu,
  # "Resend invite" (`resend`) and "Withdraw invite" (`destroy`). The id of
  # the two member actions is an OPEN `Invitation`'s: an invitation is no
  # user until it is accepted, and an accepted one is not found here.
  #
  # The services are the rules (`Invitations::`): `users.manage`, the groups
  # a non-owner may assign or not, mail being ready, the address being free,
  # and the token's life (a resend moves `sent_at`, which kills the old link;
  # a withdrawal deletes the row). A permission refusal
  # is the 403 page, as on the rest of the Users module. The controllers
  # never see a token: the mail makes its own (`InvitesMailer`).
  #
  # A refused invite draws the Users page again with the dialog open, what
  # was typed in it and the sentence under the address; "This address is
  # already invited." comes with a Resend button for that invitation. The dialog's
  # form goes to `_top` (a whole Turbo visit, as the schedule dialog's), so
  # the dialog's `open_on_load` opens it on that visit's `turbo:load`.
  class InvitesController < BaseController
    include UsersList

    before_action -> { require_permission("users.manage") }
    before_action :set_invitation, only: %i[resend destroy]
    # Ten invites per person per three minutes (mail spec "Rate limits"), by
    # the signed-in person, not the address: everyone behind one office's
    # address invites on their own count. A resend sends an invite mail too,
    # so it counts in the SAME bucket (plan ruling T9a: one declaration, so
    # one cache key for both actions); withdrawing sends nothing and is not
    # counted.
    rate_limit to: 10, within: 3.minutes, by: -> { Current.user.id }, only: %i[create resend],
      with: -> { redirect_to admin_users_path(**admin_url_options), status: :see_other, alert: t("admin.invites.too_many") }

    def create
      result = Invitations::Invite.call(email_address: invite_params[:email_address].to_s.strip, name: invite_params[:name].presence,
        group_ids: Array(invite_params[:group_ids]), **mail_origin)

      if result.ok?
        redirect_to admin_users_path(**admin_url_options), status: :see_other,
          notice: t("admin.invites.sent", email: result.record.email_address)
      else
        forbidden_or(result) do
          @invite = result.record
          @invite_errors = result.errors
          @invite_group_ids = Array(invite_params[:group_ids]).compact_blank.map(&:to_i)
          # "Already invited" offers to resend that invitation instead.
          @invite_resend = Invitation.open.find_by(email_address: @invite.email_address) if result.errors.include?(Invitations::Invite::ALREADY_INVITED)
          load_users_list
          render "admin/users/index", status: :unprocessable_entity
        end
      end
    end

    def resend
      result = Invitations::Resend.call(@invitation, **mail_origin)

      if result.ok?
        redirect_to admin_users_path(**admin_url_options), status: :see_other, notice: t("admin.invites.resent", email: @invitation.email_address)
      else
        forbidden_or(result) do
          redirect_to admin_users_path(**admin_url_options), status: :see_other, alert: result.errors.to_sentence # i18n-ok: to_sentence joins with the locale's support.array words
        end
      end
    end

    def destroy
      email = @invitation.email_address
      result = Invitations::Withdraw.call(@invitation)

      if result.ok?
        redirect_to admin_users_path(**admin_url_options), status: :see_other, notice: t("admin.invites.withdrawn", email: email)
      else
        forbidden_or(result) do
          redirect_to admin_users_path(**admin_url_options), status: :see_other, alert: result.errors.to_sentence # i18n-ok: to_sentence joins with the locale's support.array words
        end
      end
    end

    private

    def set_invitation
      @invitation = Invitation.open.find(params[:id])
    end

    # The dialog's fields are the user form's names (`user[...]`), because its
    # Groups are the user editor's group cards.
    def invite_params
      @invite_params ||= params.fetch(:user, ActionController::Parameters.new).permit(:email_address, :name, group_ids: [])
    end

    # As the reset request (`Admin::PasswordsController#reset_mail_origin`,
    # which says why): the request's origin goes to the mail only in
    # development and test, and only when no site address is configured.
    def mail_origin
      return {} if SiteAddress.current.configured? || !PasswordsMailer.request_origin_used?

      { origin: request.base_url }
    end
  end
end
